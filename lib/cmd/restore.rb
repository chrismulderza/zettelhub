#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config'
require_relative '../debug'
require_relative '../utils'
require_relative '../git_service'
require_relative '../indexer'
require_relative '../models/note'

# Restore command for reverting a note to a previous version.
# Checks out file from a specific commit and reindexes.
class RestoreCommand
  include Debug

  # Entry point for the restore command.
  def run(*args)
    return output_help if args.first == '--help' || args.first == '-h'
    return output_completion if args.first == '--completion'

    config = Config.load_with_notebook(debug: debug?)
    notebook_path = config['notebook_path']

    # Parse arguments
    note_ref, commit, options = parse_args(args)

    if note_ref.nil? || note_ref.empty?
      $stderr.puts 'Error: Note ID or path required'
      output_help
      exit 1
    end

    if commit.nil? || commit.empty?
      $stderr.puts 'Error: Commit hash required'
      output_help
      exit 1
    end

    # Resolve note path
    note_path = resolve_note_path(config, note_ref)
    if note_path.nil?
      $stderr.puts "Error: Note not found: #{note_ref}"
      exit 1
    end

    git = GitService.new(notebook_path)
    unless git.repo?
      $stderr.puts 'Error: Notebook is not a git repository'
      $stderr.puts 'Run `zh git init` to initialize'
      exit 1
    end

    # Verify commit exists and contains this file
    content_at_commit = git.show(commit: commit, path: note_path)
    if content_at_commit.nil?
      $stderr.puts "Error: Note not found at commit #{commit[0, 7]}"
      $stderr.puts 'Use `zh history` to find valid commits for this note'
      exit 1
    end

    if options[:preview]
      preview_restore(note_path, content_at_commit, commit)
    else
      perform_restore(config, git, note_path, commit)
    end
  end

  private

  # Parses command arguments into note ref, commit, and options.
  # First positional argument is note_ref, second is commit (must match git hash pattern).
  def parse_args(args)
    options = {
      preview: false
    }
    note_ref = nil
    commit = nil
    positional = []

    i = 0
    while i < args.length
      case args[i]
      when '--preview', '-p'
        options[:preview] = true
        i += 1
      else
        if args[i].start_with?('-')
          i += 1
        else
          positional << args[i]
          i += 1
        end
      end
    end

    # First positional is always note_ref
    note_ref = positional[0] if positional.any?

    # Second positional is commit (must match git hash pattern)
    if positional.length > 1 && positional[1] =~ /^[a-f0-9]{7,40}$/i
      commit = positional[1]
    end

    [note_ref, commit, options]
  end

  # Resolves note reference (ID or path) to absolute path.
  def resolve_note_path(config, note_ref)
    notebook_path = config['notebook_path']

    # Try as note ID first
    path = Utils.note_path_by_id(config, note_ref)
    return path if path && File.exist?(path)

    # Try as relative path
    full_path = File.expand_path(note_ref, notebook_path)
    return full_path if File.exist?(full_path)

    # Try as absolute path
    return note_ref if File.exist?(note_ref)

    nil
  end

  # Shows preview of what would be restored.
  def preview_restore(note_path, content_at_commit, commit)
    puts "\e[1mPreview: Restore to commit #{commit[0, 7]}\e[0m"
    puts "File: #{note_path}"
    puts

    # Read current content
    current_content = File.exist?(note_path) ? File.read(note_path) : ''

    if current_content == content_at_commit
      puts 'No changes would be made (content is identical)'
      return
    end

    # Show diff between current and target
    puts "\e[33mChanges that would be applied:\e[0m"
    puts

    # Create a simple unified diff
    current_lines = current_content.lines
    target_lines = content_at_commit.lines

    # Show line count changes
    puts "Current: #{current_lines.length} lines"
    puts "Target:  #{target_lines.length} lines"
    puts

    # Show first few lines of target
    puts "\e[36mContent at commit #{commit[0, 7]}:\e[0m"
    puts '-' * 40
    target_lines.first(30).each { |line| puts line }
    puts '...' if target_lines.length > 30
    puts '-' * 40
    puts
    puts "\e[33mRun without --preview to apply this restore\e[0m"
  end

  # Performs the actual restore operation.
  def perform_restore(config, git, note_path, commit)
    notebook_path = config['notebook_path']
    relative_path = note_path.sub("#{notebook_path}/", '')

    # Create backup of current version
    if File.exist?(note_path)
      backup_content = File.read(note_path)
      debug_print("Current content backed up (#{backup_content.length} bytes)")
    end

    # Checkout file from commit
    result = git.checkout(path: note_path, commit: commit)

    unless result[:success]
      $stderr.puts "Error: Failed to restore: #{result[:message]}"
      exit 1
    end

    puts "Restored #{relative_path} to commit #{commit[0, 7]}"

    # Reindex the note
    begin
      note = Note.new(path: note_path)
      indexer = Indexer.new(config)
      indexer.index_note(note)
      debug_print("Reindexed note: #{note.id}")
      puts 'Note reindexed'
    rescue StandardError => e
      $stderr.puts "Warning: Failed to reindex note: #{e.message}"
      debug_print("Reindex error: #{e.message}")
    end

    # Suggest committing the restore
    puts
    puts 'Tip: Run `zh git commit -m "Restore note to previous version"` to save this change'
  end

  # Outputs completion candidates.
  def output_completion
    puts '--preview --help'
  end

  # Outputs help text.
  def output_help
    puts <<~HELP
      USAGE
        zh restore <note-id|path> <commit> [options]

      DESCRIPTION
        Restore a note to a previous version from git history.
        The note will be reverted to its content at the specified commit.

        Use `zh history <note>` to find commit hashes.

      OPTIONS
        --preview, -p    Show what would be restored without making changes
        --help, -h       Show this help

      ARGUMENTS
        note-id|path     Note ID or file path
        commit           Commit hash to restore from (at least 7 characters)

      EXAMPLES
        zh restore abc12345 a1b2c3d
        zh restore abc12345 a1b2c3d --preview
        zh restore notes/meeting.md a1b2c3d

      WORKFLOW
        1. zh history abc12345          # Find the commit to restore
        2. zh restore abc12345 a1b2c3d --preview  # Preview changes
        3. zh restore abc12345 a1b2c3d  # Perform restore
        4. zh git commit -m "Restore"   # Commit the restore
    HELP
  end
end

RestoreCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
