#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config'
require_relative '../debug'
require_relative '../utils'
require_relative '../git_service'

# Diff command for viewing changes to a note.
# Shows uncommitted changes or diff at a specific commit.
class DiffCommand
  include Debug

  # Entry point for the diff command.
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

    # Get diff
    if commit
      # Diff at specific commit
      show_commit_diff(git, note_path, commit, notebook_path, options)
    elsif options[:staged]
      # Staged changes
      diff = git.diff(path: note_path, staged: true)
      display_diff(diff, options)
    else
      # Uncommitted changes (working tree)
      diff = git.diff(path: note_path)
      display_diff(diff, options)
    end
  end

  private

  # Parses command arguments into note ref, commit, and options.
  # First positional argument is note_ref, second is commit (if matches git hash pattern).
  def parse_args(args)
    options = {
      staged: false,
      color: true,
      context: 3
    }
    note_ref = nil
    commit = nil
    positional = []

    i = 0
    while i < args.length
      case args[i]
      when '--staged', '-s'
        options[:staged] = true
        i += 1
      when '--no-color'
        options[:color] = false
        i += 1
      when '-U', '--context'
        options[:context] = args[i + 1].to_i if args[i + 1]
        i += 2
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

    # Second positional is commit if it looks like a git hash
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

  # Shows diff at a specific commit.
  def show_commit_diff(git, note_path, commit, notebook_path, options)
    relative_path = note_path.sub("#{notebook_path}/", '')

    # Get commit info
    commits = git.log(path: note_path, limit: 1)
    commit_info = commits.find { |c| c[:hash].start_with?(commit) }

    if commit_info
      puts "\e[1mCommit: #{commit_info[:hash][0, 7]}\e[0m"
      puts "Author: #{commit_info[:author]}"
      puts "Date:   #{commit_info[:date]}"
      puts "Message: #{commit_info[:message]}"
      puts
    end

    # Show diff between commit and its parent
    diff = git.diff(path: note_path, commit: "#{commit}^..#{commit}")

    if diff.nil? || diff.strip.empty?
      # This might be the first commit, show file content instead
      content = git.show(commit: commit, path: note_path)
      if content
        puts "\e[33mFile added in this commit:\e[0m"
        puts content
      else
        puts 'No changes found for this file in this commit'
      end
    else
      display_diff(diff, options)
    end
  end

  # Displays diff output with optional coloring.
  def display_diff(diff, options)
    if diff.nil? || diff.strip.empty?
      puts 'No changes'
      return
    end

    # Check for delta or diff-so-fancy for better output
    if options[:color] && Utils.command_available?('delta')
      IO.popen(['delta'], 'r+') do |io|
        io.write(diff)
        io.close_write
        puts io.read
      end
    elsif options[:color] && Utils.command_available?('diff-so-fancy')
      IO.popen(['diff-so-fancy'], 'r+') do |io|
        io.write(diff)
        io.close_write
        puts io.read
      end
    else
      # Basic coloring
      diff.each_line do |line|
        if options[:color]
          case line
          when /^\+(?!\+\+)/
            print "\e[32m#{line}\e[0m"
          when /^-(?!--)/
            print "\e[31m#{line}\e[0m"
          when /^@@/
            print "\e[36m#{line}\e[0m"
          when /^(diff|index|---|\+\+\+)/
            print "\e[1m#{line}\e[0m"
          else
            print line
          end
        else
          print line
        end
      end
    end
  end

  # Outputs completion candidates.
  def output_completion
    puts '--staged --no-color --help'
  end

  # Outputs help text.
  def output_help
    puts <<~HELP
      USAGE
        zh diff <note-id|path> [commit] [options]

      DESCRIPTION
        Show changes to a note. Without a commit hash, shows uncommitted
        changes in the working tree. With a commit hash, shows the changes
        made in that specific commit.

        If delta or diff-so-fancy are installed, they will be used for
        better diff formatting.

      OPTIONS
        --staged, -s     Show staged changes (ready to commit)
        --no-color       Disable colored output
        --help, -h       Show this help

      ARGUMENTS
        note-id|path     Note ID or file path
        commit           Optional commit hash to show diff at

      EXAMPLES
        zh diff abc12345
        zh diff notes/meeting.md
        zh diff abc12345 --staged
        zh diff abc12345 a1b2c3d
        zh diff abc12345 --no-color
    HELP
  end
end

DiffCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
