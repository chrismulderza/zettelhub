#!/usr/bin/env ruby
# frozen_string_literal: true

require 'sqlite3'
require_relative '../config'
require_relative '../utils'
require_relative '../debug'

# Resolve command: return the absolute file path for a note ID.
# Used by editors (e.g., Neovim) for wikilink navigation.
class ResolveCommand
  include Debug

  # Main entry point. Resolves note ID to absolute file path.
  def run(*args)
    return output_completion(args) if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    note_arg = args.find { |a| !a.to_s.start_with?('-') }
    if note_arg.to_s.strip.empty?
      $stderr.puts 'Usage: zh resolve NOTE_ID'
      exit 1
    end

    config = Config.load_with_notebook(debug: debug?)
    notebook_path = config['notebook_path']
    db_path = Config.index_db_path(notebook_path)

    unless File.exist?(db_path)
      debug_print('No index found')
      exit 1
    end

    db = SQLite3::Database.new(db_path)
    note_id = Utils.resolve_wikilink_to_id(note_arg.to_s.strip, db)

    unless note_id
      debug_print("Note not found: #{note_arg}")
      exit 1
    end

    # Get the file path
    row = db.execute('SELECT path FROM notes WHERE id = ?', [note_id]).first
    db.close

    unless row
      debug_print("Note path not found for ID: #{note_id}")
      exit 1
    end

    relative_path = row[0]
    absolute_path = File.join(notebook_path, relative_path)

    unless File.exist?(absolute_path)
      debug_print("File not found: #{absolute_path}")
      exit 1
    end

    puts absolute_path
  end

  private

  # Prints completion candidates for shell completion.
  def output_completion(_args)
    puts '--help -h'
  end

  # Prints command-specific usage and options to stdout.
  def output_help
    puts <<~HELP
      Resolve a note ID to its absolute file path

      USAGE:
          zh resolve NOTE_ID

      DESCRIPTION:
          Returns the absolute file path for a note given its ID, title, or alias.
          Used by editors for wikilink navigation (e.g., gf in Neovim).
          Exits with code 1 if the note is not found.

      OPTIONS:
          --help, -h     Show this help message
          --completion   Output shell completion candidates

      EXAMPLES:
          zh resolve abc12345
          zh resolve "My Note Title"

      EXIT CODES:
          0  Success, path printed to stdout
          1  Note not found or index missing
    HELP
  end
end

ResolveCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
