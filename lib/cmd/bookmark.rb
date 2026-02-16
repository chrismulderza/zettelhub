#!/usr/bin/env ruby
# frozen_string_literal: true

require 'erb'
require 'fileutils'
require 'json'
require 'net/http'
require 'openssl'
require 'ostruct'
require 'sqlite3'
require 'uri'

begin
  require 'nokogiri'
rescue LoadError
  # Optional: meta description fetch is skipped when nokogiri is not installed
end

require_relative '../config'
require_relative '../debug'
require_relative '../indexer'
require_relative '../models/note'
require_relative '../utils'

# Bookmark command: interactive browser, add, export (Netscape bookmarks.html; optional Buku).
class BookmarkCommand
  include Debug

  REQUIRED_TOOLS_BROWSER = %w[filter].freeze
  REQUIRED_TOOLS_ADD = %w[editor].freeze

  # Handles --completion and --help; dispatches to browser, add, export, or refresh subcommand.
  def run(*args)
    return output_completion if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    sub = args.first
    rest = args[1..] || []
    if sub == 'add'
      return output_help if rest.first == '--help' || rest.first == '-h'
      run_add(rest)
    elsif sub == 'export'
      return output_help if rest.include?('--help') || rest.include?('-h')
      run_export(rest)
    elsif sub == 'refresh'
      return output_help if rest.include?('--help') || rest.include?('-h')
      run_refresh(rest)
    else
      run_browser(args)
    end
  end

  private

  # Interactive browser: fzf over bookmarks, open in editor/reader/open.
  def run_browser(_args)
    config = Config.load(debug: debug?)
    REQUIRED_TOOLS_BROWSER.each do |tool_key|
      executable = Config.get_tool_command(config, tool_key)
      next if executable.to_s.strip.empty?
      msg = "Error: tool '#{tool_key}' (#{executable}) is required for zh bookmark. Install #{executable} and try again."
      Utils.require_command!(executable, msg)
    end

    db_path = Config.index_db_path(config['notebook_path'])
    unless File.exist?(db_path)
      $stderr.puts "Error: Index database not found. Run `zh reindex` first."
      exit 1
    end

    rows = query_bookmarks(db_path)
    if rows.empty?
      puts 'No bookmarks found.'
      return
    end

    delimiter = Config.get_engine_db_result_delimiter(config)
    list = rows.map { |r| [r[:id], r[:title], r[:path]].join(delimiter) }.join("\n")
    debug_print("Bookmark list: #{rows.size} row(s)")

    filter_exec = Config.get_tool_command(config, 'filter')
    filter_opts = Config.get_tool_module_opts(config, 'filter', 'bookmark')
    filter_cmd = [
      filter_exec,
      *filter_opts,
      '--delimiter', delimiter,
      '--with-nth', '1,2,3',
      '--accept-nth', '1',
      '--prompt', 'Bookmark> '
    ].compact

    selected = nil
    IO.popen(ENV.to_h, filter_cmd, 'r+') do |io|
      io.puts list
      io.close_write
      selected = io.read.chomp.strip
    end

    return if selected.empty?

    id = selected.split(delimiter, 2).first&.strip
    return if id.to_s.empty?

    uri = Utils.get_metadata_attribute(db_path, id, 'uri')
    unless uri.to_s.strip.empty?
      open_uri(uri.strip)
    else
      $stderr.puts "No URI found for bookmark #{id}"
      exit 1
    end
  end

  def open_uri(uri)
    host_os = RbConfig::CONFIG['host_os'] || ''
    if host_os =~ /darwin|mac/i
      system('open', uri)
    else
      system('xdg-open', uri)
    end
  end

  def query_bookmarks(db_path)
    db = SQLite3::Database.new(db_path)
    db.results_as_hash = true
    rows = db.execute(
      "SELECT id, path, title, metadata FROM notes WHERE json_extract(metadata, '$.type') = 'bookmark' ORDER BY title"
    )
    db.close
    rows.map do |row|
      {
        id: row['id'],
        path: row['path'],
        title: (row['title'] || '').strip
      }
    end
  end

  # Returns bookmarks with full metadata for refresh: id, path, full_path, uri, title, tags, description.
  def query_bookmarks_with_metadata(db_path, notebook_path)
    db = SQLite3::Database.new(db_path)
    db.results_as_hash = true
    rows = db.execute(
      "SELECT id, path, title, metadata FROM notes WHERE json_extract(metadata, '$.type') = 'bookmark' ORDER BY title"
    )
    db.close
    notebook_path = File.expand_path(notebook_path)
    rows.map do |row|
      meta = JSON.parse(row['metadata'] || '{}')
      rel_path = row['path'].to_s
      {
        id: row['id'],
        path: rel_path,
        full_path: File.join(notebook_path, rel_path),
        uri: (meta['uri'] || '').to_s.strip,
        title: (row['title'] || meta['title'] || '').to_s.strip,
        tags: Array(meta['tags']).map(&:to_s),
        description: (meta['description'] || '').to_s.strip
      }
    end
  end

  # Creates new bookmark from URL; optionally fetches description; opens in editor.
  def run_add(args)
    config = Config.load(debug: debug?)
    REQUIRED_TOOLS_ADD.each do |tool_key|
      executable = Config.get_tool_command(config, tool_key)
      next if executable.to_s.strip.empty?
      msg = "Error: tool '#{tool_key}' (#{executable}) is required for zh bookmark add. Install #{executable} and try again."
      Utils.require_command!(executable, msg)
    end

    uri_str, title, tags, description, title_provided, tags_provided, description_provided = parse_add_args(args)
    uri_str = prompt_uri if uri_str.to_s.strip.empty?
    uri_str = uri_str.to_s.strip
    if uri_str.empty?
      $stderr.puts 'Error: URI is required.'
      exit 1
    end

    # Prompt for title, tags, description when not provided
    title = prompt_title unless title_provided
    tags = prompt_tags unless tags_provided
    description = prompt_description unless description_provided
    title ||= ''
    tags ||= []
    description ||= ''

    validate_uri(uri_str)
    debug_print("Add bookmark: uri=#{uri_str} title=#{title}")

    template_config = get_template_config(config, 'bookmark')
    template_file = Utils.find_template_file!(config['notebook_path'], template_config['template_file'], debug: debug?)
    content = render_bookmark_template(template_file, uri: uri_str, title: title.to_s, tags: tags || [], description: description.to_s, config: config)
    filepath = create_bookmark_file(config, template_config, content)
    debug_print("Created: #{filepath}")

    maybe_fetch_description(filepath, uri_str)
    index_note(config, filepath)
    puts "Bookmark created: #{filepath}"

    editor_cmd = build_editor_command(config, File.expand_path(filepath), '1')
    system(editor_cmd)
  end

  def parse_add_args(args)
    uri_str = nil
    title = nil
    tags = nil
    description = nil
    title_provided = false
    tags_provided = false
    description_provided = false
    i = 0
    while i < args.length
      case args[i]
      when '--title', '-t'
        title_provided = true
        title = args[i + 1] if i + 1 < args.length
        i += 2
      when '--tags'
        tags_provided = true
        tags = args[i + 1].to_s.split(',').map(&:strip).reject(&:empty?) if i + 1 < args.length
        i += 2
      when '--description', '-d'
        description_provided = true
        description = args[i + 1] if i + 1 < args.length
        i += 2
      else
        uri_str = args[i] unless args[i].to_s.start_with?('--')
        i += 1
      end
    end
    [uri_str, title, tags, description, title_provided, tags_provided, description_provided]
  end

  def prompt_uri
    if Utils.command_available?('gum')
      `gum input --placeholder "Enter bookmark URL"`.strip
    else
      print 'Enter bookmark URL: '
      ($stdin.gets || '').chomp
    end
  end

  def prompt_title
    if Utils.command_available?('gum')
      `gum input --placeholder "Enter bookmark title"`.strip
    else
      print 'Enter bookmark title: '
      ($stdin.gets || '').chomp
    end
  end

  def prompt_tags
    if Utils.command_available?('gum')
      input = `gum input --placeholder "Enter tags (comma-separated)"`.strip
      input.to_s.split(',').map(&:strip).reject(&:empty?)
    else
      print 'Enter tags (comma-separated): '
      input = ($stdin.gets || '').chomp
      input.to_s.split(',').map(&:strip).reject(&:empty?)
    end
  end

  def prompt_description
    if Utils.command_available?('gum')
      `gum input --placeholder "Enter description (optional)"`.strip
    else
      print 'Enter description (optional): '
      ($stdin.gets || '').chomp
    end
  end

  def validate_uri(uri_str)
    URI(uri_str)
  rescue URI::InvalidURIError => e
    $stderr.puts "Warning: URI validation failed: #{e.message}"
    # Proceed anyway (fail gracefully)
  end

  def get_template_config(config, type)
    template_config = Config.get_template(config, type, debug: debug?)
    unless template_config
      puts "Template not found: #{type}"
      exit 1
    end
    template_config
  end

  def format_tags_for_yaml(tags)
    return '[]' if tags.nil? || tags.empty?
    "[#{tags.map { |t| "\"#{t.to_s.gsub('"', '\\"')}\"" }.join(', ')}]"
  end

  def render_bookmark_template(template_file, uri:, title: '', tags: [], description: '', config: nil)
    template = ERB.new(File.read(template_file))
    date_format = config ? Config.get_engine_date_format(config) : Config.default_engine_date_format
    vars = Utils.current_time_vars(date_format: date_format)
    vars['uri'] = uri
    vars['title'] = title
    vars['tags'] = format_tags_for_yaml(tags)
    vars['description'] = description
    vars['type'] = 'bookmark'
    alias_pattern = config ? Config.get_engine_default_alias(config) : Config.default_engine_default_alias
    vars['aliases'] = Utils.interpolate_pattern(alias_pattern, vars)
    vars['content'] ||= ''
    context = OpenStruct.new(vars)
    replacement_char = config ? Config.get_engine_slugify_replacement(config) : Config.default_engine_slugify_replacement
    context.define_singleton_method(:slugify) { |text| Utils.slugify(text, replacement_char: replacement_char) }
    template.result(context.instance_eval { binding })
  end

  def create_bookmark_file(config, template_config, content)
    metadata, body = Utils.parse_front_matter(content)
    default_tags = metadata.dig('config', 'default_tags') || []
    input_tags = metadata['tags'] || []
    metadata['tags'] = (Array(default_tags) + Array(input_tags)).uniq
    vars = Utils.current_time_vars.merge('type' => 'bookmark').merge(metadata)
    effective_alias = metadata.dig('config', 'default_alias') || Config.get_engine_default_alias(config)
    metadata['aliases'] = Utils.interpolate_pattern(effective_alias, vars)
    metadata_without_config = metadata.dup
    metadata_without_config.delete('config')
    content = Utils.reconstruct_note_content(metadata_without_config, body)

    path_pattern = metadata.dig('config', 'path') || 'bookmarks/{id}-{title}.md'
    filepath_relative = Utils.interpolate_pattern(path_pattern, vars)
    filepath = File.join(config['notebook_path'], filepath_relative)
    FileUtils.mkdir_p(File.dirname(filepath))
    File.write(filepath, content)
    filepath
  end

  # Returns meta description string or nil. Uses Nokogiri if available; ignores SSL errors.
  def fetch_meta_description(uri_str)
    return nil unless defined?(Nokogiri)
    uri = URI(uri_str)
    return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

    body = nil
    ssl_opts = uri.scheme == 'https' ? { use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE } : { use_ssl: false }
    Net::HTTP.start(uri.host, uri.port, **ssl_opts, open_timeout: 3, read_timeout: 5) do |http|
      body = http.get(uri.request_uri).body
    end
    doc = Nokogiri::HTML(body)
    desc = doc.at_css('meta[name="description"]')&.attr('content')&.to_s&.strip
    desc.empty? ? nil : desc
  rescue StandardError => e
    debug_print("Could not fetch meta description: #{e.message}")
    nil
  end

  def maybe_fetch_description(filepath, uri_str)
    desc = fetch_meta_description(uri_str)
    return if desc.nil?

    metadata, body_content = Utils.parse_front_matter(File.read(filepath))
    metadata['description'] = desc
    File.write(filepath, Utils.reconstruct_note_content(metadata, body_content))
    debug_print("Updated description from meta for #{filepath}")
  end

  # Returns false only for HTTP 4xx/5xx. Returns true for 2xx/3xx or on connection/timeout (do not mark stale).
  def uri_reachable?(uri_str)
    uri = URI(uri_str)
    return true unless %w[http https].include?(uri.scheme)

    ssl_opts = uri.scheme == 'https' ? { use_ssl: true, verify_mode: OpenSSL::SSL::VERIFY_NONE } : { use_ssl: false }
    response = nil
    Net::HTTP.start(uri.host, uri.port, **ssl_opts, open_timeout: 5, read_timeout: 5) do |http|
      response = http.request_head(uri.request_uri)
    end
    code = response.code.to_i
    if code >= 400
      debug_print("URI unreachable: #{uri_str} (#{code})")
      return false
    end
    true
  rescue StandardError => e
    debug_print("URI check skipped (connection/timeout): #{e.message}")
    true
  end

  def build_editor_command(config, filepath, line = '1')
    executable = Config.get_tool_command(config, 'editor')
    opts = Config.get_tool_module_opts(config, 'editor', 'add')
    args = Config.get_tool_module_args(config, 'editor', 'add')
    args = args.gsub('{path}', filepath).gsub('{line}', line)
    Utils.build_tool_invocation(executable, opts, args)
  end

  def index_note(config, filepath)
    note = Note.new(path: filepath)
    Indexer.new(config).index_note(note)
  end

  # Refreshes stale bookmarks: fetches meta description, updates file and reindexes.
  def run_refresh(_args)
    config = Config.load(debug: debug?)
    db_path = Config.index_db_path(config['notebook_path'])
    unless File.exist?(db_path)
      $stderr.puts "Error: Index database not found. Run `zh reindex` first."
      exit 1
    end
    notebook_path = config['notebook_path']
    rows = query_bookmarks_with_metadata(db_path, notebook_path)
    total = 0
    marked_stale = 0
    descriptions_updated = 0

    rows.each do |row|
      uri = row[:uri]
      next if uri.empty?
      scheme = begin
        URI(uri).scheme
      rescue URI::InvalidURIError
        nil
      end
      unless %w[http https].include?(scheme)
        debug_print("Skipping non-http(s) URI: #{uri}")
        next
      end

      full_path = row[:full_path]
      unless File.exist?(full_path)
        debug_print("Skipping missing file: #{full_path}")
        next
      end

      total += 1
      content = File.read(full_path)
      metadata, body = Utils.parse_front_matter(content)
      metadata = metadata.dup
      modified = false

      unless uri_reachable?(uri)
        tags = Array(metadata['tags']).map(&:to_s)
        unless tags.include?('stale')
          tags << 'stale'
          metadata['tags'] = tags
          modified = true
        end
        title = (metadata['title'] || row[:title]).to_s.strip
        unless title.start_with?('Stale-')
          metadata['title'] = "Stale-#{title}"
          modified = true
        end
        if modified
          marked_stale += 1
          write_note_and_reindex(full_path, metadata, body, config)
        end
      end

      desc = (metadata['description'] || '').to_s.strip
      if desc.empty?
        fetched = fetch_meta_description(uri)
        if fetched && !fetched.empty?
          metadata['description'] = fetched
          descriptions_updated += 1
          write_note_and_reindex(full_path, metadata, body, config)
        end
      end
    end

    puts "Refreshed #{total} bookmark(s); #{marked_stale} marked stale; #{descriptions_updated} description(s) updated."
  end

  def write_note_and_reindex(path, metadata, body, config)
    content = Utils.reconstruct_note_content(metadata, body)
    File.write(path, content)
    index_note(config, path)
  end

  # Exports bookmarks to Netscape bookmarks.html (or optional Buku).
  def run_export(args)
    config = Config.load(debug: debug?)
    output_path = nil
    i = 0
    while i < args.length
      if args[i] == '--output' && i + 1 < args.length
        output_path = args[i + 1]
        i += 2
      else
        i += 1
      end
    end
    output_path ||= File.join(Dir.pwd, 'bookmarks.html')
    db_path = Config.index_db_path(config['notebook_path'])
    unless File.exist?(db_path)
      $stderr.puts "Error: Index database not found. Run `zh reindex` first."
      exit 1
    end

    rows = query_bookmarks_for_export(db_path)
    html = build_netscape_bookmarks_html(rows)
    File.write(output_path, html)
    puts "Exported #{rows.size} bookmark(s) to #{output_path}"
  end

  def query_bookmarks_for_export(db_path)
    db = SQLite3::Database.new(db_path)
    db.results_as_hash = true
    rows = db.execute(<<~SQL)
      SELECT id, path, title, metadata
      FROM notes
      WHERE json_extract(metadata, '$.type') = 'bookmark'
      ORDER BY json_extract(metadata, '$.date') ASC, title ASC
    SQL
    db.close
    notebook_path = File.expand_path(File.join(File.dirname(db_path), '..'))
    rows.map do |row|
      meta = JSON.parse(row['metadata'] || '{}')
      full_path = File.join(notebook_path, row['path'].to_s)
      date_ts = begin
        if meta['date'].to_s.strip != ''
          Time.parse(meta['date'].to_s).to_i
        elsif File.exist?(full_path)
          File.mtime(full_path).to_i
        else
          Time.now.to_i
        end
      rescue StandardError
        Time.now.to_i
      end
      {
        id: row['id'],
        uri: meta['uri'] || '',
        title: (row['title'] || '').strip,
        description: (meta['description'] || '').to_s.strip,
        date: date_ts
      }
    end
  end

  def build_netscape_bookmarks_html(rows)
    out = []
    out << '<!DOCTYPE NETSCAPE-Bookmark-file-1>'
    out << '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">'
    out << '<TITLE>Bookmarks</TITLE>'
    out << '<H1>Bookmarks</H1>'
    out << '<DL><p>'
    rows.each do |r|
      ts = r[:date].is_a?(Integer) ? r[:date] : Time.now.to_i
      out << %(<DT><A HREF="#{escape_html(r[:uri])}" ADD_DATE="#{ts}" LAST_MODIFIED="#{ts}">#{escape_html(r[:title])}</A>)
    end
    out << '</DL><p>'
    out.join("\n")
  end

  def escape_html(s)
    s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
  end

  # Prints completion candidates (add, export, refresh) for shell completion.
  def output_completion
    puts 'add export refresh --help -h'
  end

  # Prints command-specific usage and options to stdout.
  def output_help
    puts <<~HELP
      Bookmark management: browse, add, export, refresh

      USAGE:
          zh bookmark              Interactive bookmark browser (select to open in browser)
          zh bookmark add [URL] [OPTIONS]
          zh bookmark export [--output PATH]
          zh bookmark refresh

      DESCRIPTION:
          With no arguments, runs an interactive browser: lists bookmarks, on Enter opens
          the selected bookmark's URI (open on macOS, xdg-open on Linux).
          add: create a new bookmark from URL; optionally fetch description from page meta.
          export: write Netscape bookmarks.html from indexed bookmarks.
          refresh: validate http(s) URIs are reachable; mark unreachable as stale (tag + title prefix).
                  If a bookmark's description is empty, try to fetch it from the page.

      OPTIONS (add):
          --title, -t TITLE   Bookmark title
          --tags TAGS        Comma-separated tags
          --description, -d Description (or leave empty to try fetching from page)

      OPTIONS (export):
          --output PATH      Output path (default: bookmarks.html in current directory)

      OPTIONS (global):
          --help, -h         Show this help
          --completion       Output shell completion candidates

      EXAMPLES:
          zh bookmark
          zh bookmark add https://example.com
          zh bookmark add https://example.com --title "Example" --tags "ref, web"
          zh bookmark export --output ~/Desktop/bookmarks.html
          zh bookmark refresh
    HELP
  end
end

BookmarkCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
