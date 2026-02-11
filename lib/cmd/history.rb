#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'shellwords'
require_relative '../config'
require_relative '../debug'
require_relative '../utils'
require_relative '../git_service'

# History command for viewing git history of a note.
# Shows commits, allows interactive selection to view diffs.
class HistoryCommand
  include Debug

  # Entry point for the history command.
  def run(*args)
    return output_help if args.first == '--help' || args.first == '-h'
    return output_completion if args.first == '--completion'

    config = Config.load_with_notebook(debug: debug?)
    notebook_path = config['notebook_path']

    # Parse arguments
    note_ref, options = parse_args(args, config)

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

    # Get history
    commits = git.log(path: note_path, limit: options[:limit])

    if commits.empty?
      puts 'No history found for this note'
      exit 0
    end

    # Display based on format
    if options[:interactive]
      interactive_history(commits, note_path, config, git)
    else
      display_history(commits, options[:format])
    end
  end

  private

  # Parses command arguments into note reference and options hash.
  def parse_args(args, config)
    options = {
      format: 'list',
      interactive: true,
      limit: Config.get_git_history_limit(config)
    }
    note_ref = nil

    i = 0
    while i < args.length
      case args[i]
      when '--limit', '-n'
        options[:limit] = args[i + 1].to_i if args[i + 1]
        i += 2
      when '--list'
        options[:format] = 'list'
        options[:interactive] = false
        i += 1
      when '--table'
        options[:format] = 'table'
        options[:interactive] = false
        i += 1
      when '--json'
        options[:format] = 'json'
        options[:interactive] = false
        i += 1
      when '--format'
        options[:format] = args[i + 1] if args[i + 1]
        options[:interactive] = false
        i += 2
      else
        note_ref = args[i] unless args[i].start_with?('-')
        i += 1
      end
    end

    [note_ref, options]
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

  # Displays history in non-interactive format.
  def display_history(commits, format)
    case format
    when 'json'
      puts JSON.pretty_generate(commits)
    when 'table'
      display_table(commits)
    else
      display_list(commits)
    end
  end

  # Displays history as simple list.
  def display_list(commits)
    commits.each do |commit|
      date = format_date(commit[:date])
      puts "#{commit[:hash][0, 7]} #{date} #{commit[:message]}"
    end
  end

  # Displays history as formatted table.
  def display_table(commits)
    # Header
    puts format('%-7s  %-10s  %-20s  %s', 'COMMIT', 'DATE', 'AUTHOR', 'MESSAGE')
    puts '-' * 70

    commits.each do |commit|
      date = format_date(commit[:date])
      author = commit[:author][0, 20]
      message = commit[:message][0, 40]
      puts format('%-7s  %-10s  %-20s  %s', commit[:hash][0, 7], date, author, message)
    end
  end

  # Formats ISO date to short format.
  def format_date(iso_date)
    return '' if iso_date.nil?
    # Parse ISO date and format as YYYY-MM-DD
    date = Date.parse(iso_date.to_s)
    date.strftime('%Y-%m-%d')
  rescue StandardError
    iso_date.to_s[0, 10]
  end

  # Interactive history browser with fzf.
  def interactive_history(commits, note_path, config, git)
    filter_executable = Config.get_tool_command(config, 'filter')
    unless Utils.command_available?(filter_executable)
      $stderr.puts 'Warning: fzf not found, falling back to list format'
      display_list(commits)
      return
    end

    notebook_path = config['notebook_path']
    relative_path = note_path.sub("#{notebook_path}/", '')

    # Format commits for fzf (hash|date|author|message)
    input = commits.map do |commit|
      date = format_date(commit[:date])
      "#{commit[:hash][0, 7]} | #{date} | #{commit[:author]} | #{commit[:message]}"
    end.join("\n")

    # Build preview command to show diff at that commit
    preview_cmd = "git -C #{notebook_path.shellescape} show --color=always {1}:#{relative_path.shellescape} 2>/dev/null || echo 'File not in this commit'"

    # Build fzf command
    filter_cmd = [
      filter_executable,
      '--ansi',
      '--delimiter', '|',
      '--preview', preview_cmd,
      '--preview-window', 'up:60%',
      '--header', 'History: Enter=show diff | Ctrl-C=exit',
      '--prompt', 'Commit> '
    ]

    debug_print("Filter command: #{filter_cmd.inspect}")
    debug_print("Input: #{input}")

    # Run fzf
    selected = nil
    IO.popen(ENV.to_h, filter_cmd, 'r+') do |io|
      io.puts input
      io.close_write
      selected = io.read.strip
    end

    return if selected.nil? || selected.empty?

    # Extract commit hash and show diff
    commit_hash = selected.split('|').first.strip
    show_commit_diff(git, commit_hash, note_path, notebook_path)
  end

  # Shows diff for a specific commit.
  def show_commit_diff(git, commit_hash, note_path, notebook_path)
    puts "\n\e[1mCommit: #{commit_hash}\e[0m"
    puts '-' * 40

    # Get the diff for this commit
    relative_path = note_path.sub("#{notebook_path}/", '')

    # Show the diff between this commit and its parent
    diff_output = git.diff(path: note_path, commit: "#{commit_hash}^..#{commit_hash}")

    if diff_output.nil? || diff_output.strip.empty?
      # Try to show the file content at this commit instead
      content = git.show(commit: commit_hash, path: note_path)
      if content
        puts "\e[33mFile content at this commit:\e[0m"
        puts content
      else
        puts 'No changes in this commit for this file'
      end
    else
      puts diff_output
    end
  end

  # Outputs completion candidates.
  def output_completion
    # Return common options
    puts '--limit --list --table --json --help'
  end

  # Outputs help text.
  def output_help
    puts <<~HELP
      USAGE
        zh history <note-id|path> [options]

      DESCRIPTION
        View git history for a specific note. Shows commits that modified
        the note, with dates, authors, and messages.

        Interactive mode (default) uses fzf to browse commits and preview
        file content at each commit.

      OPTIONS
        --limit, -n N    Maximum commits to show (default: 20)
        --list           Output as simple list (non-interactive)
        --table          Output as formatted table (non-interactive)
        --json           Output as JSON (non-interactive)
        --format FMT     Output format: list, table, json
        --help, -h       Show this help

      EXAMPLES
        zh history abc12345
        zh history notes/meeting.md
        zh history abc12345 --limit 50
        zh history abc12345 --list
        zh history abc12345 --json
    HELP
  end
end

HistoryCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
