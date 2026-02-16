#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config'
require_relative '../indexer'
require_relative '../models/organization'
require_relative '../models/account'
require_relative '../utils'
require_relative '../debug'
require 'json'
require 'sqlite3'

# Organization command for managing organizations and accounts.
# Provides: browse, add, tree, parent, subs, ancestors, descendants.
class OrgCommand
  include Debug

  REQUIRED_TOOLS = %w[filter].freeze

  # Main entry point.
  def run(*args)
    return output_completion if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    subcommand = args.shift || 'browse'

    case subcommand
    when 'add'
      run_add(args)
    when 'list'
      run_list(args)
    when 'tree'
      run_tree(args)
    when 'parent'
      run_parent(args)
    when 'subs', 'subsidiaries'
      run_subs(args)
    when 'ancestors'
      run_ancestors(args)
    when 'descendants'
      run_descendants(args)
    when 'browse'
      run_browse(args)
    else
      # Treat as tree if it looks like an ID
      if subcommand =~ /^[a-f0-9]{6,}$/i
        run_tree([subcommand] + args)
      else
        run_browse([subcommand] + args)
      end
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

    orgs = load_organizations(db_path)
    if orgs.empty?
      puts 'No organizations found.'
      exit 0
    end

    # Format for fzf: path\t[type] name < parent (path hidden via --with-nth)
    lines = orgs.map do |o|
      filepath = File.join(notebook_path, o[:path])
      parent = o[:parent_name].to_s.empty? ? '' : " < #{o[:parent_name]}"
      "#{filepath}\t[#{o[:type]}] #{o[:name]}#{parent}"
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
    end
  end

  # Create new organization note.
  def run_add(args)
    # Determine type: organization or account
    type = 'organization'
    args.each_with_index do |arg, i|
      if arg == '--type' && args[i + 1]
        type = args[i + 1]
        args.delete_at(i + 1)
        args.delete_at(i)
        break
      end
    end

    # Delegate to add command
    require_relative 'add'
    add_args = [type] + args
    AddCommand.new.run(*add_args)
  end

  # List organizations in compact format.
  def run_list(args)
    config = Config.load(debug: debug?)
    notebook_path = config['notebook_path']
    db_path = Config.index_db_path(notebook_path)

    unless File.exist?(db_path)
      puts 'No index found. Run `zh reindex` first.'
      exit 1
    end

    orgs = load_organizations(db_path)
    format = args.include?('--json') ? :json : :table

    if format == :json
      puts JSON.pretty_generate(orgs)
    else
      puts format('%<id>-10s %<type>-12s %<name>-30s %<parent>s', id: 'ID', type: 'TYPE', name: 'NAME', parent: 'PARENT')
      puts '-' * 80
      orgs.each do |o|
        puts format('%<id>-10s %<type>-12s %<name>-30s %<parent>s',
                    id: o[:id][0, 8],
                    type: o[:type],
                    name: o[:name].to_s[0, 28],
                    parent: o[:parent_name].to_s[0, 20])
      end
    end
  end

  # Display organization hierarchy tree.
  def run_tree(args)
    note_id = args.first
    unless note_id
      puts 'Usage: zh org tree NOTE_ID'
      exit 1
    end

    config = Config.load(debug: debug?)
    notebook_path = config['notebook_path']
    db_path = Config.index_db_path(notebook_path)

    unless File.exist?(db_path)
      puts 'No index found. Run `zh reindex` first.'
      exit 1
    end

    db = SQLite3::Database.new(db_path)
    root = Utils.load_note_by_id(db, note_id)
    unless root
      puts "Organization not found: #{note_id}"
      db.close
      exit 1
    end

    # Find the ultimate root (traverse up)
    current = root
    while (parent_id = Utils.parent_org_id(current))
      parent = Utils.load_note_by_id(db, parent_id)
      break unless parent

      current = parent
    end

    # Print tree from root
    print_tree(current, db, '', true, note_id)
    db.close
  end

  # Show parent organization.
  def run_parent(args)
    note_id = args.first
    unless note_id
      puts 'Usage: zh org parent NOTE_ID'
      exit 1
    end

    config = Config.load(debug: debug?)
    db_path = Config.index_db_path(config['notebook_path'])

    unless File.exist?(db_path)
      puts 'No index found. Run `zh reindex` first.'
      exit 1
    end

    db = SQLite3::Database.new(db_path)
    note = Utils.load_note_by_id(db, note_id)
    unless note
      puts "Organization not found: #{note_id}"
      db.close
      exit 1
    end

    parent_id = Utils.parent_org_id(note)
    if parent_id
      parent = Utils.load_note_by_id(db, parent_id)
      if parent
        puts "#{parent.title} (#{parent.id})"
      else
        puts "Parent ID: #{parent_id} (not found in index)"
      end
    else
      puts 'No parent organization'
    end
    db.close
  end

  # List direct subsidiaries.
  def run_subs(args)
    note_id = args.first
    unless note_id
      puts 'Usage: zh org subs NOTE_ID'
      exit 1
    end

    config = Config.load(debug: debug?)
    db_path = Config.index_db_path(config['notebook_path'])

    unless File.exist?(db_path)
      puts 'No index found. Run `zh reindex` first.'
      exit 1
    end

    db = SQLite3::Database.new(db_path)
    note = Utils.load_note_by_id(db, note_id)
    unless note
      puts "Organization not found: #{note_id}"
      db.close
      exit 1
    end

    sub_ids = Utils.subsidiary_ids(note)
    if sub_ids.empty?
      puts 'No subsidiaries'
    else
      sub_ids.each do |sub_id|
        sub = Utils.load_note_by_id(db, sub_id)
        if sub
          puts "#{sub.title} (#{sub.id})"
        else
          puts "#{sub_id} (not found)"
        end
      end
    end
    db.close
  end

  # List all ancestors.
  def run_ancestors(args)
    note_id = args.first
    unless note_id
      puts 'Usage: zh org ancestors NOTE_ID'
      exit 1
    end

    config = Config.load(debug: debug?)
    db_path = Config.index_db_path(config['notebook_path'])

    unless File.exist?(db_path)
      puts 'No index found. Run `zh reindex` first.'
      exit 1
    end

    db = SQLite3::Database.new(db_path)
    note = Utils.load_note_by_id(db, note_id)
    unless note
      puts "Organization not found: #{note_id}"
      db.close
      exit 1
    end

    ancestor_ids = Utils.ancestor_ids(note, db)
    if ancestor_ids.empty?
      puts 'No ancestors (this is a root organization)'
    else
      ancestor_ids.each_with_index do |anc_id, i|
        anc = Utils.load_note_by_id(db, anc_id)
        indent = '  ' * i
        if anc
          puts "#{indent}#{anc.title} (#{anc.id})"
        else
          puts "#{indent}#{anc_id} (not found)"
        end
      end
    end
    db.close
  end

  # List all descendants.
  def run_descendants(args)
    note_id = args.first
    unless note_id
      puts 'Usage: zh org descendants NOTE_ID'
      exit 1
    end

    config = Config.load(debug: debug?)
    db_path = Config.index_db_path(config['notebook_path'])

    unless File.exist?(db_path)
      puts 'No index found. Run `zh reindex` first.'
      exit 1
    end

    db = SQLite3::Database.new(db_path)
    note = Utils.load_note_by_id(db, note_id)
    unless note
      puts "Organization not found: #{note_id}"
      db.close
      exit 1
    end

    desc_ids = Utils.descendant_ids(note, db)
    if desc_ids.empty?
      puts 'No descendants (this is a leaf organization)'
    else
      desc_ids.each do |desc_id|
        desc = Utils.load_note_by_id(db, desc_id)
        if desc
          puts "#{desc.title} (#{desc.id})"
        else
          puts "#{desc_id} (not found)"
        end
      end
    end
    db.close
  end

  # Recursively prints organization tree.
  def print_tree(node, db, prefix, is_last, highlight_id = nil)
    connector = is_last ? '└── ' : '├── '
    marker = node.id == highlight_id ? ' *' : ''
    puts "#{prefix}#{connector}#{node.title} (#{node.id})#{marker}"

    child_ids = Utils.subsidiary_ids(node)
    return if child_ids.empty?

    child_prefix = prefix + (is_last ? '    ' : '│   ')
    child_ids.each_with_index do |child_id, i|
      child = Utils.load_note_by_id(db, child_id)
      next unless child

      print_tree(child, db, child_prefix, i == child_ids.size - 1, highlight_id)
    end
  end

  # Loads organizations from database.
  def load_organizations(db_path)
    db = SQLite3::Database.new(db_path)
    rows = db.execute("SELECT id, path, title, metadata FROM notes WHERE json_extract(metadata, '$.type') IN ('organization', 'account')")
    db.close

    rows.map do |id, path, title, metadata_json|
      meta = JSON.parse(metadata_json || '{}')
      parent_link = meta['parent']
      parent_name = Utils.extract_title_from_wikilink(parent_link)
      {
        id: id,
        path: path,
        title: title,
        name: meta['name'] || title,
        type: meta['type'] || 'organization',
        website: meta['website'],
        industry: meta['industry'],
        parent: parent_link,
        parent_name: parent_name,
        subsidiary_count: Array(meta['subsidiaries']).size,
        tags: Array(meta['tags'])
      }
    end
  end

  # Validates required tools are available.
  def validate_tools(config)
    REQUIRED_TOOLS.each do |tool_key|
      executable = Config.get_tool_command(config, tool_key)
      next if executable.to_s.strip.empty?

      msg = "Error: tool '#{tool_key}' (#{executable}) is required for zh org. Install #{executable} and try again."
      Utils.require_command!(executable, msg)
    end
  end

  # Builds editor command.
  def build_editor_command(config, filepath, line = '1')
    executable = Config.get_tool_command(config, 'editor')
    opts = Config.get_tool_module_opts(config, 'editor', 'org')
    args = Config.get_tool_module_args(config, 'editor', 'org')
    args = args.to_s.empty? ? '{path}' : args
    args = args.gsub('{path}', filepath).gsub('{line}', line)
    Utils.build_tool_invocation(executable, opts || [], args)
  end

  # Builds preview command for fzf. Uses bat if available, falls back to cat.
  def build_preview_command(config)
    previewer_available = Utils.command_available?(Config.get_tool_command(config, 'preview'))
    if previewer_available
      preview_exec = Config.get_tool_command(config, 'preview')
      preview_opts = Config.get_tool_module_opts(config, 'preview', 'org') || []
      preview_args = Config.get_tool_module_args(config, 'preview', 'org')
      preview_args = preview_args.to_s.empty? ? '{1}' : preview_args
    else
      preview_exec = 'cat'
      preview_opts = []
      preview_args = '{1}'
    end
    Utils.build_tool_invocation(preview_exec, preview_opts, preview_args)
  end

  # Outputs completion candidates.
  def output_completion
    puts 'add list tree parent subs subsidiaries ancestors descendants browse --help -h'
  end

  # Outputs help text.
  def output_help
    puts <<~HELP
      Manage organizations and accounts

      USAGE:
          zh org [SUBCOMMAND] [OPTIONS]

      SUBCOMMANDS:
          browse              Interactive browser (default)
          add                 Create new organization
          list                List all organizations/accounts
          tree NOTE_ID        Display hierarchy tree
          parent NOTE_ID      Show parent organization
          subs NOTE_ID        List direct subsidiaries
          ancestors NOTE_ID   List all ancestors
          descendants NOTE_ID List all descendants

      OPTIONS:
          --help, -h          Show this help message
          --completion        Output shell completion candidates

      ADD OPTIONS:
          --type TYPE         organization or account (default: organization)

      LIST OPTIONS:
          --json              Output as JSON

      EXAMPLES:
          zh org                        Browse organizations interactively
          zh org add                    Create new organization
          zh org add --type account     Create new account
          zh org list                   List all organizations
          zh org tree abc123            Show hierarchy tree for abc123
          zh org parent abc123          Show parent of abc123
          zh org subs abc123            List subsidiaries of abc123
          zh org ancestors abc123       List all ancestors
          zh org descendants abc123     List all descendants
    HELP
  end
end

OrgCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
