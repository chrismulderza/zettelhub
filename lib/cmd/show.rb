#!/usr/bin/env ruby
# frozen_string_literal: true

require 'sqlite3'
require 'json'
require 'erb'
require_relative '../config'
require_relative '../utils'
require_relative '../debug'

# Show command: display note content through a preview template.
# Supports type-specific templates for formatted output.
class ShowCommand
  include Debug

  # Main entry point. Renders note through preview template.
  def run(*args)
    return output_completion(args) if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    # Parse options
    json_output = args.delete('--json')
    raw_output = args.delete('--raw')
    lines_idx = args.index('--lines')
    max_lines = nil
    if lines_idx
      args.delete_at(lines_idx)
      max_lines = args.delete_at(lines_idx)&.to_i
    end
    template_idx = args.index('--template')
    custom_template = nil
    if template_idx
      args.delete_at(template_idx)
      custom_template = args.delete_at(template_idx)
    end

    note_arg = args.find { |a| !a.to_s.start_with?('-') }
    if note_arg.to_s.strip.empty?
      $stderr.puts 'Usage: zh show NOTE_ID'
      exit 1
    end

    config = Config.load_with_notebook(debug: debug?)
    notebook_path = config['notebook_path']
    db_path = Config.index_db_path(notebook_path)

    unless File.exist?(db_path)
      $stderr.puts 'No index found. Run zh reindex first.'
      exit 1
    end

    db = SQLite3::Database.new(db_path)
    note_id = Utils.resolve_wikilink_to_id(note_arg.to_s.strip, db)

    unless note_id
      $stderr.puts "Note not found: #{note_arg}"
      exit 1
    end

    # Get note data
    row = db.execute('SELECT path, title, metadata FROM notes WHERE id = ?', [note_id]).first
    db.close

    unless row
      $stderr.puts "Note not found in index: #{note_id}"
      exit 1
    end

    relative_path, title, metadata_json = row
    absolute_path = File.join(notebook_path, relative_path)

    unless File.exist?(absolute_path)
      $stderr.puts "File not found: #{absolute_path}"
      exit 1
    end

    # Parse the note
    content = File.read(absolute_path)
    metadata, body = Utils.parse_front_matter(content)
    metadata ||= {}
    note_type = metadata['type'] || 'note'

    debug_print("Note ID: #{note_id}, Type: #{note_type}, Path: #{relative_path}")

    # JSON output
    if json_output
      output = metadata.merge(
        'id' => note_id,
        'path' => relative_path,
        'absolute_path' => absolute_path,
        'body' => body
      )
      puts JSON.pretty_generate(output)
      return
    end

    # Raw output
    if raw_output
      output = body.to_s
      output = output.lines.first(max_lines).join if max_lines
      puts output
      return
    end

    # Template-based output
    template_content = find_preview_template(config, notebook_path, note_type, custom_template)

    if template_content
      output = render_template(template_content, metadata, body, note_id, relative_path)
    else
      # Fallback: simple formatted output
      output = format_fallback(metadata, body, note_id)
    end

    output = output.lines.first(max_lines).join if max_lines
    puts output
  end

  private

  # Find preview template by searching template directories.
  def find_preview_template(config, notebook_path, note_type, custom_template)
    # Search order: local, global, bundled
    search_paths = []

    if custom_template
      # Custom template specified
      search_paths << File.join(notebook_path, '.zh', 'templates', "#{custom_template}.erb")
      search_paths << File.join(Dir.home, '.config', 'zh', 'templates', "#{custom_template}.erb")
      search_paths << File.join(__dir__, '..', 'templates', "#{custom_template}.erb")
    else
      # Type-specific then default
      [note_type, 'default'].each do |tmpl_name|
        search_paths << File.join(notebook_path, '.zh', 'templates', 'preview', "#{tmpl_name}.erb")
        search_paths << File.join(Dir.home, '.config', 'zh', 'templates', 'preview', "#{tmpl_name}.erb")
        search_paths << File.join(__dir__, '..', 'templates', 'preview', "#{tmpl_name}.erb")
      end
    end

    search_paths.each do |path|
      debug_print("Checking template: #{path}")
      if File.exist?(path)
        debug_print("Using template: #{path}")
        return File.read(path)
      end
    end

    nil
  end

  # Render template with note data.
  def render_template(template_content, metadata, body, note_id, path)
    # Build binding with all metadata fields
    b = binding

    # Core fields
    id = note_id
    title = metadata['title'] || ''
    type = metadata['type'] || 'note'
    date = metadata['date'] || ''
    tags = Array(metadata['tags'])
    description = metadata['description'] || ''
    aliases = metadata['aliases'] || []

    # Type-specific fields (person)
    full_name = metadata['full_name'] || title
    emails = Array(metadata['emails'])
    phones = Array(metadata['phones'])
    organization = metadata['organization'] || ''
    role = metadata['role'] || ''
    birthday = metadata['birthday'] || ''
    address = metadata['address'] || ''
    website = metadata['website'] || ''

    # Type-specific fields (organization)
    name = metadata['name'] || title
    industry = metadata['industry'] || ''
    parent = metadata['parent'] || ''
    subsidiaries = Array(metadata['subsidiaries'])

    # Make metadata hash available
    meta = metadata

    erb = ERB.new(template_content, trim_mode: '-')
    erb.result(b)
  rescue StandardError => e
    debug_print("Template render error: #{e.message}")
    format_fallback(metadata, body, note_id)
  end

  # Simple fallback formatting when no template available.
  def format_fallback(metadata, body, note_id)
    lines = []
    title = metadata['title'] || note_id
    lines << "# #{title}"
    lines << ''

    type = metadata['type']
    date = metadata['date']
    tags = Array(metadata['tags'])

    lines << "Type: #{type}" if type && !type.empty?
    lines << "Date: #{date}" if date && !date.empty?
    lines << "Tags: #{tags.join(', ')}" if tags.any?
    lines << ''
    lines << '---'
    lines << ''
    lines << body.to_s

    lines.join("\n")
  end

  # Prints completion candidates.
  def output_completion(_args)
    puts '--json --raw --lines --template --help -h'
  end

  # Prints command-specific help.
  def output_help
    puts <<~HELP
      Display note content through a preview template

      USAGE:
          zh show NOTE_ID [OPTIONS]

      DESCRIPTION:
          Renders a note through a preview template for formatted display.
          Automatically selects type-specific templates (e.g., preview/person.erb).
          Falls back to default template or simple formatting if none found.

      OPTIONS:
          --lines N      Limit output to N lines
          --raw          Output raw body without template
          --json         Output note data as JSON
          --template T   Use specific template (e.g., preview/compact)
          --help, -h     Show this help message
          --completion   Output shell completion candidates

      TEMPLATE SEARCH ORDER:
          1. {notebook}/.zh/templates/preview/{type}.erb
          2. {notebook}/.zh/templates/preview/default.erb
          3. ~/.config/zh/templates/preview/{type}.erb
          4. ~/.config/zh/templates/preview/default.erb
          5. lib/templates/preview/default.erb (bundled)

      EXAMPLES:
          zh show abc12345
          zh show abc12345 --lines 20
          zh show abc12345 --raw
          zh show abc12345 --json
          zh show "My Note" --template preview/compact
    HELP
  end
end

ShowCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
