#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config'
require_relative '../indexer'
require_relative '../models/person'
require_relative '../utils'
require_relative '../debug'
require 'json'
require 'sqlite3'

# Person command for managing contacts.
# Provides: browse, add, list, import, export, birthdays, stale, merge.
class PersonCommand
  include Debug

  REQUIRED_TOOLS = %w[filter].freeze

  # Main entry point.
  def run(*args)
    return output_completion(args) if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    subcommand = args.shift || 'browse'

    case subcommand
    when 'add'
      run_add(args)
    when 'list'
      run_list(args)
    when 'import'
      run_import(args)
    when 'export'
      run_export(args)
    when 'birthdays'
      run_birthdays(args)
    when 'stale'
      run_stale(args)
    when 'merge'
      run_merge(args)
    when 'browse'
      run_browse(args)
    else
      # Treat as browse with query
      run_browse([subcommand] + args)
    end
  end

  private

  # Interactive browser using fzf with preview.
  def run_browse(args)
    config = Config.load(debug: debug?)
    validate_tools(config)

    notebook_path = config['notebook_path']
    db_path = Config.index_db_path(notebook_path)
    unless File.exist?(db_path)
      puts 'No index found. Run `zh reindex` first.'
      exit 1
    end

    people = load_people(db_path)
    if people.empty?
      puts 'No contacts found.'
      exit 0
    end

    # Format for fzf: path\tname @ org\temail (path hidden via --with-nth)
    lines = people.map do |p|
      filepath = File.join(notebook_path, p[:path])
      org = p[:organization].to_s.empty? ? '' : " @ #{p[:organization]}"
      "#{filepath}\t#{p[:full_name]}#{org}\t#{p[:email]}"
    end

    # Build preview command
    preview_cmd = build_preview_command(config)
    debug_print("Preview command: #{preview_cmd}")

    # Run fzf with preview
    filter_executable = Config.get_tool_command(config, 'filter')
    filter_opts = [
      '--with-nth', '2..',
      '--delimiter', "\t",
      '--preview', preview_cmd,
      '--preview-window', 'right:50%:wrap'
    ]

    selected = IO.popen([filter_executable, *filter_opts], 'r+') do |io|
      io.puts lines.join("\n")
      io.close_write
      io.read.strip
    end

    return if selected.empty?

    # Extract path (first field) and open file
    filepath = selected.split("\t").first
    if File.exist?(filepath)
      editor_cmd = build_editor_command(config, filepath)
      system(editor_cmd)
      # Reindex after edit to capture changes (links, tags, content)
      index_note(config, filepath)
    end
  end

  # Create new person note.
  def run_add(args)
    # Delegate to add command with person type
    require_relative 'add'
    add_args = ['person'] + args
    AddCommand.new.run(*add_args)
  end

  # List contacts in compact format.
  def run_list(args)
    config = Config.load(debug: debug?)
    notebook_path = config['notebook_path']
    db_path = Config.index_db_path(notebook_path)

    unless File.exist?(db_path)
      puts 'No index found. Run `zh reindex` first.'
      exit 1
    end

    people = load_people(db_path)

    format = args.include?('--json') ? :json : :table

    if format == :json
      puts JSON.pretty_generate(people)
    else
      # Table format
      puts format('%<id>-10s %<name>-30s %<org>-20s %<email>s', id: 'ID', name: 'NAME', org: 'ORGANIZATION', email: 'EMAIL')
      puts '-' * 80
      people.each do |p|
        puts format('%<id>-10s %<name>-30s %<org>-20s %<email>s',
                    id: p[:id][0, 8],
                    name: p[:full_name].to_s[0, 28],
                    org: p[:organization].to_s[0, 18],
                    email: p[:email].to_s)
      end
    end
  end

  # Import contacts from vCard file.
  def run_import(args)
    filepath = args.find { |a| !a.start_with?('--') }
    unless filepath && File.exist?(filepath)
      puts 'Usage: zh person import FILE'
      puts 'Supported formats: .vcf (vCard)'
      exit 1
    end

    dry_run = args.include?('--dry-run')
    check_duplicates = args.include?('--check-duplicates')

    require_relative '../vcf_parser'
    config = Config.load(debug: debug?)

    contacts = VcfParser.parse_file(filepath)
    puts "Found #{contacts.size} contact(s) in #{filepath}"

    if dry_run
      contacts.each do |contact|
        puts "  - #{contact[:full_name]} <#{contact[:emails]&.first}>"
      end
      puts "\nDry run - no changes made."
      return
    end

    # Import each contact
    imported = 0
    contacts.each do |contact|
      if check_duplicates && duplicate_exists?(config, contact)
        puts "Skipping duplicate: #{contact[:full_name]}"
        next
      end

      create_person_from_import(config, contact)
      imported += 1
      puts "Imported: #{contact[:full_name]}"
    end

    puts "\nImported #{imported} contact(s)."
  end

  # Export contacts to vCard file.
  def run_export(args)
    output_file = nil
    tag_filter = nil
    format = 'vcf'

    i = 0
    while i < args.length
      case args[i]
      when '--output', '-o'
        output_file = args[i + 1]
        i += 2
      when '--tag'
        tag_filter = args[i + 1]
        i += 2
      when '--format'
        format = args[i + 1]
        i += 2
      else
        i += 1
      end
    end

    output_file ||= 'people.vcf'

    config = Config.load(debug: debug?)
    notebook_path = config['notebook_path']
    db_path = Config.index_db_path(notebook_path)

    unless File.exist?(db_path)
      puts 'No index found. Run `zh reindex` first.'
      exit 1
    end

    people = load_people(db_path)

    # Filter by tag if specified
    if tag_filter
      people = people.select { |p| Array(p[:tags]).include?(tag_filter) }
    end

    require_relative '../vcf_parser'
    vcards = people.map { |p| VcfParser.to_vcard(p) }
    File.write(output_file, vcards.join("\n"))
    puts "Exported #{people.size} contact(s) to #{output_file}"
  end

  # List upcoming birthdays.
  def run_birthdays(args)
    days = 30
    args.each_with_index do |arg, i|
      days = args[i + 1].to_i if arg == '--days' && args[i + 1]
    end

    config = Config.load(debug: debug?)
    db_path = Config.index_db_path(config['notebook_path'])

    unless File.exist?(db_path)
      puts 'No index found. Run `zh reindex` first.'
      exit 1
    end

    people = load_people(db_path)
    today = Date.today
    upcoming = []

    people.each do |p|
      next if p[:birthday].to_s.empty?

      begin
        bday = Date.parse(p[:birthday])
        # Get this year's birthday
        this_year_bday = Date.new(today.year, bday.month, bday.day)
        # If already passed, check next year
        this_year_bday = Date.new(today.year + 1, bday.month, bday.day) if this_year_bday < today

        days_until = (this_year_bday - today).to_i
        upcoming << { person: p, days_until: days_until, date: this_year_bday } if days_until <= days
      rescue ArgumentError
        next
      end
    end

    upcoming.sort_by! { |u| u[:days_until] }

    if upcoming.empty?
      puts "No birthdays in the next #{days} days."
    else
      puts "Upcoming birthdays (next #{days} days):"
      upcoming.each do |u|
        if u[:days_until].zero?
          puts "  TODAY: #{u[:person][:full_name]}"
        elsif u[:days_until] == 1
          puts "  TOMORROW: #{u[:person][:full_name]}"
        else
          puts "  #{u[:date].strftime('%b %d')}: #{u[:person][:full_name]} (in #{u[:days_until]} days)"
        end
      end
    end
  end

  # List stale contacts (not contacted recently).
  def run_stale(args)
    days = 90
    args.each_with_index do |arg, i|
      days = args[i + 1].to_i if arg == '--days' && args[i + 1]
    end

    config = Config.load(debug: debug?)
    db_path = Config.index_db_path(config['notebook_path'])

    unless File.exist?(db_path)
      puts 'No index found. Run `zh reindex` first.'
      exit 1
    end

    people = load_people(db_path)
    threshold = Date.today - days
    stale = []

    people.each do |p|
      if p[:last_contact].to_s.empty?
        stale << { person: p, last_contact: nil, days_since: nil }
      else
        begin
          last = Date.parse(p[:last_contact])
          days_since = (Date.today - last).to_i
          stale << { person: p, last_contact: last, days_since: days_since } if last < threshold
        rescue ArgumentError
          stale << { person: p, last_contact: nil, days_since: nil }
        end
      end
    end

    stale.sort_by! { |s| s[:days_since] || Float::INFINITY }

    if stale.empty?
      puts "No stale contacts (all contacted within #{days} days)."
    else
      puts "Stale contacts (not contacted in #{days}+ days):"
      stale.each do |s|
        if s[:last_contact].nil?
          puts "  #{s[:person][:full_name]} - never contacted"
        else
          puts "  #{s[:person][:full_name]} - #{s[:days_since]} days ago (#{s[:last_contact]})"
        end
      end
    end
  end

  # Merge duplicate contacts.
  def run_merge(args)
    if args.size < 2
      puts 'Usage: zh person merge ID1 ID2'
      puts 'Merges ID2 into ID1 (keeps ID1, deletes ID2)'
      exit 1
    end

    id1, id2 = args[0, 2]
    config = Config.load(debug: debug?)
    notebook_path = config['notebook_path']
    db_path = Config.index_db_path(notebook_path)

    db = SQLite3::Database.new(db_path)
    row1 = db.execute('SELECT path, metadata FROM notes WHERE id = ?', [id1]).first
    row2 = db.execute('SELECT path, metadata FROM notes WHERE id = ?', [id2]).first
    db.close

    unless row1 && row2
      puts 'One or both contact IDs not found.'
      exit 1
    end

    meta1 = JSON.parse(row1[1] || '{}')
    meta2 = JSON.parse(row2[1] || '{}')

    # Merge metadata (ID1 wins for conflicts)
    merged = deep_merge_metadata(meta1, meta2)

    # Update ID1 file
    path1 = File.join(notebook_path, row1[0])
    content = File.read(path1)
    _old_meta, body = Utils.parse_front_matter(content)
    File.write(path1, Utils.reconstruct_note_content(merged, body))

    # Delete ID2 file
    path2 = File.join(notebook_path, row2[0])
    File.delete(path2) if File.exist?(path2)

    # Reindex
    indexer = Indexer.new(config)
    indexer.remove_notes([id2])
    require_relative '../models/note'
    indexer.index_note(Note.new(path: path1))

    puts "Merged #{id2} into #{id1}"
    puts "Deleted: #{path2}"
  end

  # Loads people from database.
  def load_people(db_path)
    db = SQLite3::Database.new(db_path)
    rows = db.execute("SELECT id, path, title, metadata FROM notes WHERE json_extract(metadata, '$.type') = 'person'")
    db.close

    rows.map do |id, path, title, metadata_json|
      meta = JSON.parse(metadata_json || '{}')
      {
        id: id,
        path: path,
        title: title,
        full_name: meta['full_name'] || title,
        emails: Array(meta['emails']),
        email: Array(meta['emails']).first,
        phones: Array(meta['phones']),
        organization: extract_org_name(meta['organization']),
        role: meta['role'],
        birthday: meta['birthday'],
        last_contact: meta['last_contact'],
        tags: Array(meta['tags']),
        website: meta['website']
      }
    end
  end

  # Extracts organization name from wikilink or plain text.
  def extract_org_name(org)
    return nil if org.to_s.empty?

    # If it's a wikilink [[id|name]], extract name
    if (match = org.match(/\[\[([^\]|]+)\|([^\]]+)\]\]/))
      match[2]
    elsif (match = org.match(/\[\[([^\]]+)\]\]/))
      match[1]
    else
      org
    end
  end

  # Validates required tools are available.
  def validate_tools(config)
    REQUIRED_TOOLS.each do |tool_key|
      executable = Config.get_tool_command(config, tool_key)
      next if executable.to_s.strip.empty?

      msg = "Error: tool '#{tool_key}' (#{executable}) is required for zh person. Install #{executable} and try again."
      Utils.require_command!(executable, msg)
    end
  end

  # Builds editor command.
  def build_editor_command(config, filepath, line = '1')
    executable = Config.get_tool_command(config, 'editor')
    opts = Config.get_tool_module_opts(config, 'editor', 'person')
    args = Config.get_tool_module_args(config, 'editor', 'person')
    args = args.to_s.empty? ? '{path}' : args
    args = args.gsub('{path}', filepath).gsub('{line}', line)
    Utils.build_tool_invocation(executable, opts || [], args)
  end

  # Reindexes a single note after editing. Updates index with new content, links, tags.
  def index_note(config, filepath)
    require_relative '../indexer'
    require_relative '../models/note'
    note = Note.new(path: filepath)
    indexer = Indexer.new(config)
    indexer.index_note(note)
    debug_print("Reindexed: #{filepath}")
  end

  # Builds preview command for fzf. Uses bat if available, falls back to cat.
  def build_preview_command(config)
    previewer_available = Utils.command_available?(Config.get_tool_command(config, 'preview'))
    if previewer_available
      preview_exec = Config.get_tool_command(config, 'preview')
      preview_opts = Config.get_tool_module_opts(config, 'preview', 'person') || []
      preview_args = Config.get_tool_module_args(config, 'preview', 'person')
      preview_args = preview_args.to_s.empty? ? '{1}' : preview_args
    else
      preview_exec = 'cat'
      preview_opts = []
      preview_args = '{1}'
    end
    Utils.build_tool_invocation(preview_exec, preview_opts, preview_args)
  end

  # Checks if a duplicate contact exists.
  def duplicate_exists?(config, contact)
    db_path = Config.index_db_path(config['notebook_path'])
    return false unless File.exist?(db_path)

    db = SQLite3::Database.new(db_path)
    # Check by name or email
    name = contact[:full_name].to_s.downcase
    email = contact[:emails]&.first&.downcase

    rows = db.execute("SELECT metadata FROM notes WHERE json_extract(metadata, '$.type') = 'person'")
    db.close

    rows.any? do |row|
      meta = JSON.parse(row[0] || '{}')
      (meta['full_name']&.downcase == name) ||
        (email && Array(meta['emails']).map(&:downcase).include?(email))
    end
  end

  # Creates a person note from imported data.
  def create_person_from_import(config, contact)
    require_relative 'add'
    add_cmd = AddCommand.new

    # Prepare tags
    tags = ['contact', 'person', 'imported']
    tags += contact[:tags] if contact[:tags]

    # Build template variables
    template_vars = {
      'full_name' => contact[:full_name],
      'emails' => format_array_for_yaml(contact[:emails] || []),
      'phones' => format_array_for_yaml(contact[:phones] || []),
      'organization' => contact[:organization].to_s,
      'role' => contact[:role].to_s,
      'birthday' => contact[:birthday].to_s,
      'address' => contact[:address].to_s,
      'website' => contact[:website].to_s,
      'linkedin' => contact.dig(:social, :linkedin).to_s,
      'github' => contact.dig(:social, :github).to_s,
      'twitter' => contact.dig(:social, :twitter).to_s,
      'relationships' => '[]',
      'last_contact' => '',
      'content' => contact[:notes].to_s
    }

    template_config = Config.get_template(config, 'person', debug: debug?)
    template_file = Utils.find_template_file!(config['notebook_path'], template_config['template_file'], debug: debug?)
    content = add_cmd.send(:render_template, template_file, 'person', title: contact[:full_name], tags: tags, config: config)

    # Inject imported values
    metadata, body = Utils.parse_front_matter(content)
    template_vars.each do |key, value|
      metadata[key] = value unless value.to_s.empty?
    end

    # Reconstruct and write
    add_cmd.create_note_file(config, template_config, 'person', Utils.reconstruct_note_content(metadata, body))
  end

  # Formats array for YAML inline format.
  def format_array_for_yaml(arr)
    return '[]' if arr.nil? || arr.empty?

    "[#{arr.map { |v| "\"#{v.to_s.gsub('"', '\\"')}\"" }.join(', ')}]"
  end

  # Deep merges metadata, combining arrays.
  def deep_merge_metadata(meta1, meta2)
    result = meta1.dup
    meta2.each do |key, value|
      if result[key].is_a?(Array) && value.is_a?(Array)
        result[key] = (result[key] + value).uniq
      elsif result[key].nil? || result[key].to_s.empty?
        result[key] = value
      end
    end
    result
  end

  # Outputs completion candidates.
  # Returns __FILE__ for options that take file paths.
  def output_completion(args = [])
    prev = args[1]
    case prev
    when '--output', '-o'
      puts '__FILE__'
    else
      puts 'add list import export birthdays stale merge browse --help -h'
    end
  end

  # Outputs help text.
  def output_help
    puts <<~HELP
      Manage contacts (people)

      USAGE:
          zh person [SUBCOMMAND] [OPTIONS]

      SUBCOMMANDS:
          browse            Interactive browser (default)
          add [NAME]        Create new contact
          list              List all contacts
          import FILE       Import from vCard (.vcf)
          export            Export to vCard
          birthdays         Show upcoming birthdays
          stale             Show contacts not recently contacted
          merge ID1 ID2     Merge two contacts

      OPTIONS:
          --help, -h        Show this help message
          --completion      Output shell completion candidates

      LIST OPTIONS:
          --json            Output as JSON

      IMPORT OPTIONS:
          --dry-run         Preview without creating files
          --check-duplicates  Skip contacts that already exist

      EXPORT OPTIONS:
          --output, -o FILE  Output filename (default: people.vcf)
          --tag TAG          Only export contacts with this tag

      BIRTHDAYS OPTIONS:
          --days N          Look ahead N days (default: 30)

      STALE OPTIONS:
          --days N          Threshold in days (default: 90)

      EXAMPLES:
          zh person                   Browse contacts interactively
          zh person add               Create new contact (prompts for info)
          zh person list              List all contacts
          zh person list --json       List as JSON
          zh person import contacts.vcf
          zh person export --output work.vcf --tag work
          zh person birthdays --days 7
          zh person stale --days 60
          zh person merge abc123 def456
    HELP
  end
end

PersonCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
