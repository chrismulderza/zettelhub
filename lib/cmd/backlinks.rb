#!/usr/bin/env ruby
# frozen_string_literal: true

require 'sqlite3'
require 'set'
require 'json'
require_relative '../config'
require_relative '../utils'
require_relative '../debug'

# Backlinks command: list notes that link to a given note (incoming links).
# Supports multiple output formats for editor integration.
class BacklinksCommand
  include Debug

  # Handles --completion and --help; resolves note and prints incoming links.
  def run(*args)
    return output_completion(args) if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    # Parse options
    json_output = args.delete('--json')
    format_idx = args.index('--format')
    output_format = 'default'
    if format_idx
      args.delete_at(format_idx)
      output_format = args.delete_at(format_idx) || 'default'
    end

    note_arg = args.find { |a| !a.to_s.start_with?('-') }
    if note_arg.to_s.strip.empty?
      $stderr.puts 'Usage: zh backlinks NOTE_ID'
      $stderr.puts 'NOTE_ID can be note id (8-char hex), title, or alias.'
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
    db.close

    unless note_id
      $stderr.puts "Note not found: #{note_arg}"
      exit 1
    end

    db = SQLite3::Database.new(db_path)
    rows = db.execute(
      'SELECT l.source_id, l.link_type, n.path, n.title FROM links l ' \
      'LEFT JOIN notes n ON l.source_id = n.id ' \
      'WHERE l.target_id = ? ORDER BY l.link_type, n.title',
      [note_id]
    )
    db.close

    if rows.empty?
      if json_output
        puts '[]'
      else
        puts "No backlinks to note #{note_id}."
      end
      return
    end

    # Build result data
    results = rows.map do |source_id, link_type, path, title|
      {
        'id' => source_id,
        'path' => path,
        'absolute_path' => path ? File.join(notebook_path, path) : nil,
        'title' => title || source_id,
        'link_type' => link_type,
        'broken' => path.nil?
      }
    end

    # Output based on format
    if json_output
      puts JSON.generate(results)
    elsif output_format == 'path'
      results.each do |r|
        puts r['absolute_path'] if r['absolute_path']
      end
    elsif output_format == 'full'
      results.each do |r|
        broken = r['broken'] ? ' (broken)' : ''
        puts "#{r['id']}\t#{r['path']}\t#{r['title']}\t#{r['link_type']}#{broken}"
      end
    else
      # Default format
      results.each do |r|
        broken = r['broken'] ? ' (broken)' : ''
        puts "#{r['id']}  #{r['link_type']}#{broken}"
      end
    end
  end

  private

  # Prints completion candidates for shell completion.
  def output_completion(_args)
    puts '--json --format --help -h'
  end

  # Prints command-specific usage and options to stdout.
  def output_help
    puts <<~HELP
      List backlinks (notes that link to this note)

      USAGE:
          zh backlinks NOTE_ID [OPTIONS]

      DESCRIPTION:
          Shows all notes that link to the given note (incoming links).
          NOTE_ID can be the note's 8-character id, title, or alias.
          Marks broken links when the source note is missing from the index.

      OPTIONS:
          --json         Output as JSON array
          --format FMT   Output format: default, path, full
                         - default: id and link_type
                         - path: absolute file paths only
                         - full: tab-separated id, path, title, link_type
          --help, -h     Show this help message
          --completion   Output shell completion candidates

      EXAMPLES:
          zh backlinks abc12345
          zh backlinks abc12345 --json
          zh backlinks abc12345 --format path
          zh backlinks "My Note Title" --format full
    HELP
  end
end

BacklinksCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
