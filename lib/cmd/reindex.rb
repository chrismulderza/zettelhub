#!/usr/bin/env ruby
# frozen_string_literal: true

require 'pathname'
require 'set'
require_relative '../config'
require_relative '../indexer'
require_relative '../models/note'
require_relative '../debug'

# Reindex command for rebuilding the note index
class ReindexCommand
  include Debug

  # Handles --completion and --help; rescans notebook and rebuilds index.
  # Supports --file <path> for single-file indexing (used by Neovim auto-index).
  def run(*args)
    return output_completion(args) if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    # Single file mode: zh reindex --file <path>
    if args[0] == '--file' && args[1]
      return index_single_file(args[1])
    end

    config = Config.load_with_notebook(debug: debug?)
    notebook_path = config['notebook_path']

    # Find all markdown files recursively
    markdown_files = find_markdown_files(notebook_path)
    debug_print("notebook_path: #{notebook_path}, found #{markdown_files.length} markdown files")
    puts "Found #{markdown_files.length} markdown files"

    # Index each file
    indexer = Indexer.new(config)
    indexed_count = 0
    error_count = 0
    ids_on_disk = Set.new

    markdown_files.each do |file_path|
      begin
        note = Note.new(path: file_path)
        debug_print("indexing: #{file_path} (id: #{note.id})")
        indexer.index_note(note)
        indexed_count += 1
        ids_on_disk << note.id
      rescue StandardError => e
        error_count += 1
        $stderr.puts "Warning: Failed to index #{file_path}: #{e.message}"
        debug_print("Error details: #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
      end
    end

    debug_print("Indexed #{indexed_count} files, errors: #{error_count}")
    puts "Indexed #{indexed_count} files"
    puts "Skipped #{error_count} files due to errors" if error_count > 0

    # Remove index entries for files that no longer exist on disk
    db_ids = indexer.indexed_note_ids
    ids_to_remove = db_ids - ids_on_disk.to_a
    debug_print("ids_on_disk: #{ids_on_disk.size}, db_ids: #{db_ids.size}, removing #{ids_to_remove.size} orphaned: #{ids_to_remove.sort.inspect}")
    if ids_to_remove.any?
      indexer.remove_notes(ids_to_remove)
      puts "Removed #{ids_to_remove.length} orphaned entries"
    end

    # Second pass: update links (and backlinks sections) so resolution sees all notes in the index
    debug_print("Links pass: #{markdown_files.length} files")
    markdown_files.each do |file_path|
      begin
        note = Note.new(path: file_path)
        indexer.update_links_for_note(note)
      rescue StandardError => e
        debug_print("Links pass skip #{file_path}: #{e.message}")
      end
    end
  end

  private

  # Indexes a single file by path. Used for incremental indexing (e.g. Neovim on save).
  # Exits silently on error to avoid disrupting editor workflow.
  def index_single_file(filepath)
    config = Config.load_with_notebook(debug: debug?)
    unless File.exist?(filepath)
      debug_print("File not found: #{filepath}")
      return
    end

    begin
      note = Note.new(path: filepath)
      indexer = Indexer.new(config)
      indexer.index_note(note)
      indexer.update_links_for_note(note)
      debug_print("Indexed single file: #{filepath} (id: #{note.id})")
    rescue StandardError => e
      debug_print("Failed to index #{filepath}: #{e.message}")
    end
  end

  def find_markdown_files(notebook_path)
    # Use Dir.glob to recursively find all .md files
    pattern = File.join(notebook_path, '**', '*.md')
    all_files = Dir.glob(pattern)

    # Filter out files in .zh directory
    zh_prefix = "#{Config::ZH_DIRNAME}/"
    all_files.reject do |file_path|
      relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(notebook_path)).to_s
      relative_path.start_with?(zh_prefix) || relative_path.include?("/#{Config::ZH_DIRNAME}/")
    end
  end

  # Prints completion candidates for shell completion.
  # Returns __FILE__ for options that take file paths.
  def output_completion(args = [])
    prev = args[1]
    case prev
    when '--file'
      puts '__FILE__'
    else
      puts '--help -h --file'
    end
  end

  # Prints command-specific usage and options to stdout.
  def output_help
    puts <<~HELP
      Re-index all markdown files in the notebook

      USAGE:
          zh reindex
          zh reindex --file <path>

      DESCRIPTION:
          Recursively scans the notebook directory for all markdown (.md) files,
          reads their YAML frontmatter, and adds/updates entries in the SQLite
          index database. Files in the .zh directory are automatically skipped.

          Use --file to index a single file (useful for incremental updates after
          editing, e.g. from Neovim auto-index on save).

      OPTIONS:
          --file <path>   Index a single file instead of full reindex
          --help, -h      Show this help message
          --completion    Output shell completion candidates

      EXAMPLES:
          zh reindex                        Re-index all notes in the notebook
          zh reindex --file path/to/note.md Index a single file
          zh reindex --help                 Show this help message

      The reindex command will:
          - Find all .md files recursively in the notebook directory
          - Parse YAML frontmatter from each file
          - Add new notes to the index or update existing entries
          - Remove index entries for files that no longer exist on disk
          - Skip files in the .zh directory
          - Report the number of files found and indexed
          - Show warnings for files that could not be indexed
    HELP
  end
end

ReindexCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
