#!/usr/bin/env ruby
# frozen_string_literal: true

require 'sqlite3'
require 'json'
require 'pathname'
require 'shellwords'
require 'date'
require_relative '../config'
require_relative '../indexer'
require_relative '../utils'
require_relative '../debug'

# Search command for full-text search across notes
class SearchCommand
  include Debug

  # Entry: completion, help, validate query/filters, load config, execute search, display.
  def run(*args)
    if args.first == '--completion'
      # Get previous word from remaining args (passed by bash completion script)
      prev_word = args[1]
      return output_completion(prev_word)
    end
    return output_help if args.first == '--help' || args.first == '-h'

    query, filters, options = parse_args(args)

    # Query is optional if filters are provided
    has_filters = filters.values.any? { |v| !v.nil? && !v.empty? }
    if (query.nil? || query.empty?) && !has_filters
      $stderr.puts 'Error: Search query or at least one filter (--type, --tag, --date, --path) is required'
      output_help
      exit 1
    end

    config = Config.load(debug: debug?)
    options[:limit] ||= Config.get_search_limit(config)
    db_path = Config.index_db_path(config['notebook_path'])

    unless File.exist?(db_path)
      $stderr.puts "Error: Index database not found at #{db_path}"
      $stderr.puts 'Run `zh reindex` to create the index'
      exit 1
    end

    results = execute_search(db_path, query, filters, options)
    display_results(results, options)
  end

  private

  # Returns space-separated option names for shell completion.
  def get_search_options
    %w[--type --tag --date --path --format --list --table --json --limit --help -h]
  end

  # Parses argv into query, filters hash (type, tag, date, path), and options hash (format, interactive, limit). Default is interactive; --format / --list / --table / --json disable interactive.
  def parse_args(args)
    query = nil
    filters = {
      type: nil,
      tag: nil,
      date: nil,
      path: nil
    }
    options = {
      format: 'list',
      interactive: true,
      limit: nil
    }

    i = 0
    while i < args.length
      case args[i]
      when '--type'
        filters[:type] = args[i + 1] if i + 1 < args.length
        i += 2
      when '--tag'
        filters[:tag] = args[i + 1] if i + 1 < args.length
        i += 2
      when '--date'
        filters[:date] = args[i + 1] if i + 1 < args.length
        i += 2
      when '--path'
        filters[:path] = args[i + 1] if i + 1 < args.length
        i += 2
      when '--format'
        options[:format] = args[i + 1] if i + 1 < args.length
        options[:interactive] = false
        i += 2
      when '--list'
        options[:format] = 'list'
        options[:interactive] = false
        i += 1
      when '--table'
        options[:format] = 'table'
        options[:interactive] = false
        i += 1
      when '--json'
        options[:format] = 'json'
        options[:interactive] = false
        i += 1
      when '--limit'
        options[:limit] = args[i + 1].to_i if i + 1 < args.length
        i += 2
      else
        # First non-flag argument is the query
        query = args[i] unless args[i].start_with?('--')
        i += 1
      end
    end

    [query, filters, options]
  end

  # Builds FTS5 + filter SQL, executes on db, returns array of result hashes (symbol keys).
  def execute_search(db_path, query, filters, options)
    db = SQLite3::Database.new(db_path)
    db.results_as_hash = true

    has_query = !query.nil? && !query.empty?
    where_clauses = []
    params = []

    # If query is provided, use FTS5
    if has_query
      where_clauses << 'notes_fts MATCH ?'
      params << escape_fts_query(query)
    end

    # Type filter
    if filters[:type]
      where_clauses << "json_extract(n.metadata, '$.type') = ?"
      params << filters[:type]
    end

    # Tag filter - check if tags array contains the tag
    if filters[:tag]
      where_clauses << "json_extract(n.metadata, '$.tags') IS NOT NULL"
      where_clauses << "json_array_length(json_extract(n.metadata, '$.tags')) > 0"
      where_clauses << "EXISTS (SELECT 1 FROM json_each(json_extract(n.metadata, '$.tags')) WHERE value = ?)"
      params << filters[:tag]
    end

    # Date filter
    if filters[:date]
      date_condition, date_params = build_date_filter(filters[:date])
      where_clauses << date_condition
      params.concat(date_params)
    end

    # Path filter
    if filters[:path]
      where_clauses << 'n.path LIKE ?'
      params << filters[:path]
    end

    # Build SQL query - use FTS5 if query provided, otherwise query notes directly
    if has_query
      sql = <<-SQL
        SELECT n.id, n.path, n.title, n.metadata, n.filename,
               bm25(notes_fts) as rank
        FROM notes_fts
        JOIN notes n ON notes_fts.id = n.id
        WHERE #{where_clauses.join(' AND ')}
        ORDER BY rank
        LIMIT ?
      SQL
    else
      # No FTS5 query - query directly from notes table
      sql = <<-SQL
        SELECT n.id, n.path, n.title, n.metadata, n.filename,
               0.0 as rank
        FROM notes n
        WHERE #{where_clauses.join(' AND ')}
        ORDER BY json_extract(n.metadata, '$.date') DESC, n.title ASC
        LIMIT ?
      SQL
    end

    params << options[:limit]

    debug_print("SQL: #{sql}")
    debug_print("Params: #{params.inspect}")

    begin
      results = db.execute(sql, params)
      results.map do |row|
        metadata = JSON.parse(row['metadata'] || '{}')
        {
          id: row['id'],
          path: row['path'],
          title: row['title'] || '',
          type: metadata['type'] || '',
          date: metadata['date'] || '',
          tags: metadata['tags'] || [],
          filename: row['filename'] || '',
          rank: row['rank'] || 0.0
        }
      end
    rescue SQLite3::SQLException => e
      # Catch FTS5 query syntax errors
      if has_query && (e.message.include?('MATCH') || e.message.include?('unterminated') || e.message.include?('syntax error'))
        $stderr.puts "Error: Invalid search query syntax"
        $stderr.puts "FTS5 query syntax: use spaces for AND, 'OR' for OR, quotes for phrases"
        exit 1
      else
        raise
      end
    ensure
      db.close
    end
  end

  # Escapes FTS5 special characters in query string.
  def escape_fts_query(query)
    # FTS5 has special characters: ", ', \, and operators: AND, OR, NOT
    # For basic usage, we'll quote the entire query if it contains special chars
    # Users can still use FTS5 syntax if they want
    query.to_s
  end

  # Returns [sql_condition, params] for single date, month, or range.
  def build_date_filter(date_str)
    # Support formats:
    # - "2026-01-15" (single date)
    # - "2026-01" (month)
    # - "2026-01-15:2026-01-20" (range)

    if date_str.include?(':')
      # Range format
      start_date, end_date = date_str.split(':', 2)
      return [
        "json_extract(n.metadata, '$.date') BETWEEN ? AND ?",
        [start_date.strip, end_date.strip]
      ]
    elsif date_str.match?(/^\d{4}-\d{2}$/)
      # Month format (YYYY-MM)
      year, month = date_str.split('-')
      start_date = "#{year}-#{month}-01"
      # Calculate last day of month
      last_day = Date.new(year.to_i, month.to_i, -1).day
      end_date = "#{year}-#{month}-#{'%02d' % last_day}"
      return [
        "json_extract(n.metadata, '$.date') BETWEEN ? AND ?",
        [start_date, end_date]
      ]
    else
      # Single date format
      return [
        "json_extract(n.metadata, '$.date') = ?",
        [date_str]
      ]
    end
  end

  # Dispatches to interactive_search or format_list/format_table/format_json per options.
  def display_results(results, options)
    if results.empty?
      puts 'No results found'
      return
    end
    debug_print("Results: #{results.inspect}")

    if options[:interactive]
      interactive_search(results, options)
    else
      case options[:format]
      when 'json'
        format_json(results)
      when 'table'
        format_table(results)
      else
        format_list(results)
      end
    end
  end

  # Prints results as ID | Title | Path lines.
  def format_list(results)
    results.each do |result|
      puts "#{result[:id]} | #{result[:title]} | #{result[:path]}"
    end
  end

  # Prints results as aligned table (ID, Title, Type, Date, Path).
  def format_table(results)
    # Calculate column widths
    id_width = [results.map { |r| r[:id].length }.max || 8, 8].max
    title_width = [results.map { |r| r[:title].length }.max || 20, 20].max
    type_width = [results.map { |r| r[:type].length }.max || 10, 10].max
    date_width = 10
    path_width = [results.map { |r| r[:path].length }.max || 30, 30].max

    # Header
    header = format(
      "%-#{id_width}s | %-#{title_width}s | %-#{type_width}s | %-#{date_width}s | %-#{path_width}s",
      'ID', 'Title', 'Type', 'Date', 'Path'
    )
    puts header
    puts '-' * header.length

    # Rows
    results.each do |result|
      row = format(
        "%-#{id_width}s | %-#{title_width}s | %-#{type_width}s | %-#{date_width}s | %-#{path_width}s",
        result[:id],
        result[:title][0..title_width - 1],
        result[:type][0..type_width - 1],
        result[:date][0..date_width - 1],
        result[:path][0..path_width - 1]
      )
      puts row
    end
  end

  # Prints results as pretty-printed JSON.
  def format_json(results)
    puts JSON.pretty_generate(results.map do |result|
      {
        id: result[:id],
        path: result[:path],
        title: result[:title],
        type: result[:type],
        date: result[:date],
        tags: result[:tags],
        filename: result[:filename],
        rank: result[:rank]
      }
    end    )
  end

  # Runs fzf with piped results, preview, and keybindings; outputs selected path or falls back to list.
  def interactive_search(results, options)
    config = Config.load(debug: debug?)
    filter_executable = Config.get_tool_command(config, 'filter')
    unless Utils.command_available?(filter_executable)
      $stderr.puts 'Warning: filter not found, falling back to list format'
      format_list(results)
      return
    end

    notebook_path = config['notebook_path']

    # Prepare input for filter (rank | id | type | date | title | tags | full_path = 7 fields)
    filter_input = results.map do |result|
      full_path = File.join(notebook_path, result[:path])
      tags_str = (result[:tags].is_a?(Array) ? result[:tags] : []).join(', ')
      debug_print("Full path: #{full_path}")
      "#{result[:rank]} | #{result[:id]} | #{result[:type]} | #{result[:date]} | #{result[:title]} | #{tags_str} | #{full_path}"
    end.join("\n")
    debug_print("Filter input: #{filter_input}")

    previewer_available = Utils.command_available?(Config.get_tool_command(config, 'preview'))
    preview_exec = previewer_available ? Config.get_tool_command(config, 'preview') : 'cat'
    preview_opts = previewer_available ? Config.get_tool_module_opts(config, 'preview', 'search') : []
    preview_args = previewer_available ? Config.get_tool_module_args(config, 'preview', 'search') : '{-1}'
    preview_cmd = Utils.build_tool_invocation(preview_exec, preview_opts, preview_args)

    # Display format and select expression (tools.filter.search)
    display_format = Config.get_tools_filter_search_display_format(config)
    select_expression = Config.get_tools_filter_search_select_expression(config)

    # Preview window: from config
    preview_window = Config.get_tools_filter_search_preview_window(config)

    filter_opts = Config.get_tool_module_opts(config, 'filter', 'search')
    delimiter = Config.get_engine_db_result_delimiter(config)
    filter_cmd = [
      filter_executable,
      *filter_opts,
      '--delimiter', delimiter,
      '--with-nth', display_format,
      '--accept-nth', select_expression,
      '--preview', preview_cmd,
      '--prompt', 'Pattern> ',
      '--preview-window', preview_window
    ]

    # Optional static header (key hints)
    header = Config.get_tools_filter_search_header(config)
    filter_cmd.concat(['--header', header]) if header && !header.strip.empty?

    # Keybindings: default from config (with placeholders substituted) then search-specific
    editor_cmd = Utils.build_tool_invocation(
      Config.get_tool_command(config, 'editor'),
      Config.get_tool_module_opts(config, 'editor', 'search'),
      Config.get_tool_module_args(config, 'editor', 'search')
    )
    open_cmd = Utils.build_tool_invocation(
      Config.get_tool_command(config, 'open'),
      Config.get_tool_module_opts(config, 'open', 'search'),
      Config.get_tool_module_args(config, 'open', 'search')
    )
    reader_available = Utils.command_available?(Config.get_tool_command(config, 'reader'))
    reader_exec = reader_available ? Config.get_tool_command(config, 'reader') : 'less'
    reader_cmd = Utils.build_tool_invocation(
      reader_exec,
      Config.get_tool_module_opts(config, 'reader', 'search'),
      Config.get_tool_module_args(config, 'reader', 'search')
    )
    raw_bindings = Config.get_tools_filter_keybindings(config)
    bind_parts = raw_bindings.map do |s|
      Config.substitute_filter_keybinding_placeholders(
        s,
        editor_command: editor_cmd,
        reader_command: reader_cmd,
        open_command: open_cmd
      )
    end
    filter_cmd.concat(['--bind', bind_parts.join(',')]) if bind_parts.any?

    debug_print("Filter command: #{filter_cmd.to_s}")
    debug_print("Filter input: #{filter_input}")

    # Execute filter
    IO.popen(ENV.to_h, filter_cmd, 'r+') do |io|
      io.puts filter_input
      io.close_write
      selected = io.read.chomp
      unless selected.empty?
        # Output is whatever --accept-nth specifies (e.g. last field with default -1)
        puts selected.strip
      end
    end
  rescue StandardError => e
    $stderr.puts "Error in interactive search: #{e.message}"
    format_list(results)
  end

  # Outputs completion candidates for shell completion.
  def output_completion(prev_word = nil)
    # Special case: if prev_word is '--options', return available options
    if prev_word == '--options'
      puts get_search_options.join(' ')
      return
    end

    # If no previous word, return available options (user typing after command)
    if prev_word.nil? || prev_word.empty?
      puts get_search_options.join(' ')
      return
    end

    case prev_word
    when '--format'
      # Return format options
      puts 'list table json'
    when '--type'
      begin
        config = Config.load(debug: false)
        types = Config.template_types(config)
        puts types.join(' ') unless types.empty?
      rescue StandardError
        puts Config.default_template_types.join(' ')
      end
    when '--tag'
      # Return existing tags from database
      begin
        config = Config.load(debug: false)
        db_path = Config.index_db_path(config['notebook_path'])
        if File.exist?(db_path)
          db = SQLite3::Database.new(db_path)
          # Get all unique tags from metadata
          # Use json_each to extract tags from JSON arrays
          results = db.execute(<<-SQL)
            SELECT DISTINCT json_each.value as tag
            FROM notes,
            json_each(json_extract(notes.metadata, '$.tags'))
            WHERE json_extract(notes.metadata, '$.tags') IS NOT NULL
              AND json_array_length(json_extract(notes.metadata, '$.tags')) > 0
          SQL
          tags = results.map(&:first).compact.uniq.sort
          puts tags.join(' ') unless tags.empty?
          db.close
        end
      rescue StandardError => e
        debug_print("Tag completion error: #{e.message}") if debug?
        # No tags available
      end
    when '--date'
      # Return date format examples (user can type their own)
      # Could return recent dates, but for now return empty to let user type
      puts ''
    when '--path'
      # Return path examples or empty (user should type their own pattern)
      puts ''
    when '--limit'
      # Return common limit values
      puts '10 25 50 100 200'
    else
      # No specific completion needed (user is typing query or option)
      puts ''
    end
  end

  # Outputs search command help text.
  def output_help
    puts <<~HELP
      Search notes using full-text search or metadata filters

      USAGE:
          zh search [OPTIONS] [query]

      DESCRIPTION:
          Searches notes using FTS5 full-text search across title, filename, and body content,
          or filters by metadata (type, tag, date, path). At least one filter or a query is required.
          Default is interactive mode (fzf with preview). Use --list, --table, or --json to print
          results to stdout instead. When a query is provided, results are ranked by relevance
          (BM25). When only filters are used, results are ordered by date (descending) then title.

      OPTIONS:
          --type TYPE         Filter by note type (e.g., note, journal, meeting)
          --tag TAG           Filter by tag (matches if note has this tag)
          --date DATE         Filter by date
                              Formats: "2026-01-15" (single date)
                                       "2026-01" (entire month)
                                       "2026-01-15:2026-01-20" (date range)
          --path PATH         Filter by file path pattern (SQL LIKE syntax)
          --format FORMAT     Print results in format: list, table, json (disables interactive)
          --list              Print results as list (one line per note)
          --table             Print results as table
          --json              Print results as JSON
          --limit N           Maximum number of results (default from config: search_limit)
          --help, -h          Show this help message
          --completion        Output shell completion candidates

      FTS5 QUERY SYNTAX:
          - Space-separated words: "meeting notes" (AND)
          - OR operator: "meeting OR notes"
          - Phrase matching: "meeting notes"
          - Exclude words: "meeting -standup"
          - Prefix matching: "meet*"

      EXAMPLES:
          zh search "meeting notes"
          zh search --tag work
          zh search --list "meeting"
          zh search --type journal "reflection"
          zh search --tag work "project"
          zh search --date "2026-01" "review"
          zh search --type meeting --tag work
          zh search --format json "notes"
          zh search --type meeting --tag work --date "2026-01" "standup"
    HELP
  end
end

SearchCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
