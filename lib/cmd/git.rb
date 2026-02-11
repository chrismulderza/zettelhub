#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config'
require_relative '../debug'
require_relative '../utils'
require_relative '../git_service'

# Git command for notebook version control.
# Subcommands: init, status, commit, sync.
class GitCommand
  include Debug

  # Entry point for the git command.
  # Routes to subcommands: init, status, commit, sync.
  def run(*args)
    return output_help if args.empty? || args.first == '--help' || args.first == '-h'
    return output_completion if args.first == '--completion'

    subcommand = args.shift
    case subcommand
    when 'init'
      run_init(args)
    when 'status'
      run_status(args)
    when 'commit'
      run_commit(args)
    when 'sync'
      run_sync(args)
    else
      $stderr.puts "Unknown git subcommand: #{subcommand}"
      output_help
      exit 1
    end
  end

  private

  # Initializes git repository in the notebook directory.
  def run_init(args)
    return output_init_help if args.include?('--help') || args.include?('-h')

    config = Config.load_with_notebook(debug: debug?)
    notebook_path = config['notebook_path']

    remote = nil
    i = 0
    while i < args.length
      case args[i]
      when '--remote', '-r'
        remote = args[i + 1]
        i += 2
      else
        i += 1
      end
    end

    git = GitService.new(notebook_path)
    result = git.init(remote: remote)

    if result[:success]
      puts "Initialized git repository in #{notebook_path}"
      puts "Added remote: #{remote}" if remote
      puts "Created .gitignore (excludes .zh/)"
    else
      $stderr.puts "Error: #{result[:message]}"
      exit 1
    end
  end

  # Shows git status with note titles.
  def run_status(args)
    return output_status_help if args.include?('--help') || args.include?('-h')

    config = Config.load_with_notebook(debug: debug?)
    notebook_path = config['notebook_path']
    git = GitService.new(notebook_path)

    unless git.repo?
      $stderr.puts 'Error: Notebook is not a git repository'
      $stderr.puts 'Run `zh git init` to initialize'
      exit 1
    end

    status = git.status
    branch = git.current_branch || 'unknown'

    puts "On branch #{branch}"
    puts

    if status[:staged].any?
      puts 'Changes to be committed:'
      status[:staged].each do |path|
        title = get_note_title(notebook_path, path)
        puts "  \e[32m#{path}\e[0m#{title ? " (#{title})" : ''}"
      end
      puts
    end

    unstaged_modified = status[:modified] - status[:staged]
    unstaged_deleted = status[:deleted] - status[:staged]

    if unstaged_modified.any? || unstaged_deleted.any?
      puts 'Changes not staged for commit:'
      unstaged_modified.each do |path|
        title = get_note_title(notebook_path, path)
        puts "  \e[33mmodified: #{path}\e[0m#{title ? " (#{title})" : ''}"
      end
      unstaged_deleted.each do |path|
        puts "  \e[31mdeleted:  #{path}\e[0m"
      end
      puts
    end

    if status[:untracked].any?
      puts 'Untracked files:'
      status[:untracked].each do |path|
        title = get_note_title(notebook_path, path)
        puts "  \e[31m#{path}\e[0m#{title ? " (#{title})" : ''}"
      end
      puts
    end

    if status[:staged].empty? && unstaged_modified.empty? && unstaged_deleted.empty? && status[:untracked].empty?
      puts 'Nothing to commit, working tree clean'
    end
  end

  # Commits changes to the repository.
  def run_commit(args)
    return output_commit_help if args.include?('--help') || args.include?('-h')

    config = Config.load_with_notebook(debug: debug?)
    notebook_path = config['notebook_path']
    git = GitService.new(notebook_path)

    unless git.repo?
      $stderr.puts 'Error: Notebook is not a git repository'
      $stderr.puts 'Run `zh git init` to initialize'
      exit 1
    end

    message = nil
    all = false

    i = 0
    while i < args.length
      case args[i]
      when '-m', '--message'
        message = args[i + 1]
        i += 2
      when '-a', '--all'
        all = true
        i += 1
      else
        i += 1
      end
    end

    # Auto-generate message if not provided
    if message.nil? || message.strip.empty?
      status = git.status
      changed_count = (status[:modified] + status[:added] + status[:deleted] + status[:untracked]).uniq.size
      if changed_count == 0
        $stderr.puts 'Nothing to commit'
        exit 0
      end
      template = Config.get_git_commit_message_template(config)
      message = template.gsub('{changed_count}', changed_count.to_s)
    end

    result = git.commit(message: message, all: all)

    if result[:success]
      puts 'Changes committed'
      puts result[:message] if result[:message] && !result[:message].empty?
    else
      $stderr.puts "Error: #{result[:message]}"
      exit 1
    end
  end

  # Syncs with remote repository (pull then push).
  def run_sync(args)
    return output_sync_help if args.include?('--help') || args.include?('-h')

    config = Config.load_with_notebook(debug: debug?)
    notebook_path = config['notebook_path']
    git = GitService.new(notebook_path)

    unless git.repo?
      $stderr.puts 'Error: Notebook is not a git repository'
      $stderr.puts 'Run `zh git init` to initialize'
      exit 1
    end

    remote = Config.get_git_remote(config)
    branch = Config.get_git_branch(config)

    push_only = args.include?('--push-only')
    pull_only = args.include?('--pull-only')

    # Pull first (unless push-only)
    unless push_only
      puts "Pulling from #{remote}/#{branch}..."
      result = git.pull(remote: remote, branch: branch)
      if result[:success]
        puts 'Pull complete'
      else
        if result[:message]&.include?('conflict')
          $stderr.puts 'Merge conflicts detected. Please resolve manually:'
          $stderr.puts result[:message]
          exit 1
        elsif result[:message]&.include?('not found')
          puts 'No remote configured, skipping pull'
        else
          $stderr.puts "Pull failed: #{result[:message]}"
          exit 1 unless pull_only
        end
      end
    end

    # Push (unless pull-only)
    unless pull_only
      puts "Pushing to #{remote}/#{branch}..."
      result = git.push(remote: remote, branch: branch)
      if result[:success]
        puts 'Push complete'
      else
        if result[:message]&.include?('not found')
          puts 'No remote configured, skipping push'
        else
          $stderr.puts "Push failed: #{result[:message]}"
          exit 1
        end
      end
    end

    puts 'Sync complete'
  end

  # Gets note title from file if it's a markdown file.
  def get_note_title(notebook_path, relative_path)
    return nil unless relative_path.end_with?('.md')

    full_path = File.join(notebook_path, relative_path)
    return nil unless File.exist?(full_path)

    content = File.read(full_path)
    metadata, = Utils.parse_front_matter(content)
    metadata['title']
  rescue StandardError
    nil
  end

  # Outputs completion candidates for shell completion.
  def output_completion
    puts 'init status commit sync'
  end

  # Outputs main help text.
  def output_help
    puts <<~HELP
      USAGE
        zh git <subcommand> [options]

      DESCRIPTION
        Git version control for your notebook. Initialize a repository,
        view status, commit changes, and sync with a remote.

      SUBCOMMANDS
        init      Initialize git repository in notebook
        status    Show status of notes (modified, added, deleted)
        commit    Commit changes to repository
        sync      Push and pull with remote repository

      OPTIONS
        --help, -h    Show help for command or subcommand

      EXAMPLES
        zh git init
        zh git init --remote git@github.com:user/notes.git
        zh git status
        zh git commit -m "Add meeting notes"
        zh git commit --all
        zh git sync
    HELP
  end

  # Outputs init subcommand help.
  def output_init_help
    puts <<~HELP
      USAGE
        zh git init [--remote URL]

      DESCRIPTION
        Initialize a git repository in the notebook directory.
        Creates .gitignore to exclude the .zh/ directory.

      OPTIONS
        --remote, -r URL    Add remote repository URL as 'origin'
        --help, -h          Show this help

      EXAMPLES
        zh git init
        zh git init --remote git@github.com:user/notes.git
    HELP
  end

  # Outputs status subcommand help.
  def output_status_help
    puts <<~HELP
      USAGE
        zh git status

      DESCRIPTION
        Show the status of notes in the repository.
        Displays note titles alongside file paths.

      OPTIONS
        --help, -h    Show this help

      EXAMPLES
        zh git status
    HELP
  end

  # Outputs commit subcommand help.
  def output_commit_help
    puts <<~HELP
      USAGE
        zh git commit [-m MESSAGE] [--all]

      DESCRIPTION
        Commit changes to the repository.
        Auto-generates commit message if not provided.

      OPTIONS
        -m, --message MSG    Commit message
        -a, --all            Stage all changes before committing
        --help, -h           Show this help

      EXAMPLES
        zh git commit -m "Add meeting notes"
        zh git commit --all -m "Update notes"
        zh git commit --all
    HELP
  end

  # Outputs sync subcommand help.
  def output_sync_help
    puts <<~HELP
      USAGE
        zh git sync [--push-only] [--pull-only]

      DESCRIPTION
        Sync with remote repository. By default, pulls then pushes.
        Remote and branch are configured in config.yaml.

      OPTIONS
        --push-only    Only push, skip pull
        --pull-only    Only pull, skip push
        --help, -h     Show this help

      EXAMPLES
        zh git sync
        zh git sync --push-only
        zh git sync --pull-only
    HELP
  end
end

GitCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
