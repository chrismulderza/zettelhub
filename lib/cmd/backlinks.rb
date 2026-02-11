#!/usr/bin/env ruby
# frozen_string_literal: true

require 'sqlite3'
require 'set'
require_relative '../config'
require_relative '../utils'
require_relative '../debug'

# Backlinks command: list notes that link to a given note (incoming links).
class BacklinksCommand
  include Debug

  # Handles --completion and --help; resolves note and prints incoming links.
  def run(*args)
    return output_completion(args) if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    note_arg = args.find { |a| !a.to_s.start_with?('-') }
    if note_arg.to_s.strip.empty?
      $stderr.puts 'Usage: zh backlinks NOTE_ID'
      $stderr.puts 'NOTE_ID can be note id (8-char hex), title, or alias.'
      exit 1
    end

    config = Config.load_with_notebook(debug: debug?)
    db_path = Config.index_db_path(config['notebook_path'])
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
    rows = db.execute('SELECT source_id, link_type FROM links WHERE target_id = ? ORDER BY link_type, source_id', [note_id])
    db.close

    if rows.empty?
      puts "No backlinks to note #{note_id}."
      return
    end

    db = SQLite3::Database.new(db_path)
    ids_in_notes = db.execute('SELECT id FROM notes').flatten.to_set
    db.close

    rows.each do |source_id, link_type|
      broken = ids_in_notes.include?(source_id) ? '' : ' (broken)'
      puts "#{source_id}  #{link_type}#{broken}"
    end
  end

  private

  # Prints completion candidates for shell completion.
  def output_completion(args)
    puts ''
  end

  # Prints command-specific usage and options to stdout.
  def output_help
    puts <<~HELP
      List backlinks (notes that link to this note)

      USAGE:
          zh backlinks NOTE_ID

      DESCRIPTION:
          Shows all notes that link to the given note (incoming links).
          NOTE_ID can be the note's 8-character id, title, or alias.
          Marks broken links when the source note is missing from the index.

      OPTIONS:
          --help, -h     Show this help message
          --completion   Output shell completion candidates

      EXAMPLES:
          zh backlinks abc12345
          zh backlinks "My Note Title"
    HELP
  end
end

BacklinksCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
