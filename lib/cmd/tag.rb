#!/usr/bin/env ruby
# frozen_string_literal: true

require 'sqlite3'
require_relative '../config'
require_relative '../indexer'
require_relative '../models/note'
require_relative '../utils'
require_relative '../debug'
require_relative '../git_service'

# Tag command: list tags with counts; add/remove tag on a note; rename tag across notes.
class TagCommand
  include Debug

  SUBCOMMANDS = %w[list add remove rename].freeze

  # Handles --completion and --help; dispatches to list/add/remove/rename subcommands.
  def run(*args)
    return output_completion(args) if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    config = Config.load_with_notebook(debug: debug?)
    sub = args[0].to_s.strip.downcase
    sub = 'list' if sub.empty? || !SUBCOMMANDS.include?(sub)

    case sub
    when 'list'
      run_list(config)
    when 'add'
      run_add(config, args[1], args[2])
    when 'remove'
      run_remove(config, args[1], args[2])
    when 'rename'
      run_rename(config, args[1], args[2])
    else
      run_list(config)
    end
  end

  private

  def run_list(config)
    db_path = Config.index_db_path(config['notebook_path'])
    unless File.exist?(db_path)
      puts 'No index found. Run zh reindex first.'
      return
    end

    db = SQLite3::Database.new(db_path)
    results = db.execute(<<-SQL)
      SELECT TRIM(json_each.value, '"') AS tag, COUNT(*) AS cnt
      FROM notes, json_each(json_extract(notes.metadata, '$.tags'))
      WHERE json_extract(notes.metadata, '$.tags') IS NOT NULL
        AND json_array_length(json_extract(notes.metadata, '$.tags')) > 0
      GROUP BY tag
      ORDER BY cnt DESC, tag
    SQL
    db.close

    if results.empty?
      puts 'No tags in notebook.'
      return
    end

    max_count = results.map { |_tag, cnt| cnt.to_s.length }.max
    results.each do |tag, cnt|
      puts format("%#{max_count}d  %s", cnt, tag)
    end
  end

  # Adds tag to note; updates file and reindexes.
  def run_add(config, tag, note_id)
    if tag.to_s.strip.empty? || note_id.to_s.strip.empty?
      $stderr.puts 'Usage: zh tag add TAG NOTE_ID'
      exit 1
    end

    path = Utils.note_path_by_id(config, note_id)
    unless path && File.exist?(path)
      $stderr.puts "Error: Note not found: #{note_id}"
      exit 1
    end

    note = Note.new(path: path)
    metadata = note.metadata.dup
    tags = Array(metadata['tags']).map(&:to_s)
    tag_str = tag.to_s.strip
    if tags.include?(tag_str)
      puts "Tag \"#{tag_str}\" already on note #{note_id}."
      return
    end
    tags << tag_str
    metadata['tags'] = tags
    write_note_and_reindex(path, metadata, note.body, config)
    puts "Tag \"#{tag_str}\" added to note #{note_id}."
    auto_commit_change(config, [path], "Add tag '#{tag_str}' to note")
  end

  # Removes tag from note; updates file and reindexes.
  def run_remove(config, tag, note_id)
    if tag.to_s.strip.empty? || note_id.to_s.strip.empty?
      $stderr.puts 'Usage: zh tag remove TAG NOTE_ID'
      exit 1
    end

    path = Utils.note_path_by_id(config, note_id)
    unless path && File.exist?(path)
      $stderr.puts "Error: Note not found: #{note_id}"
      exit 1
    end

    note = Note.new(path: path)
    metadata = note.metadata.dup
    tags = Array(metadata['tags']).map(&:to_s).reject { |t| t == tag.to_s.strip }
    metadata['tags'] = tags
    write_note_and_reindex(path, metadata, note.body, config)
    puts "Tag \"#{tag}\" removed from note #{note_id}."
    auto_commit_change(config, [path], "Remove tag '#{tag}' from note")
  end

  # Renames tag across all notes; updates files and reindexes.
  def run_rename(config, old_tag, new_tag)
    if old_tag.to_s.strip.empty? || new_tag.to_s.strip.empty?
      $stderr.puts 'Usage: zh tag rename OLD_TAG NEW_TAG'
      exit 1
    end

    old_str = old_tag.to_s.strip
    new_str = new_tag.to_s.strip
    if old_str == new_str
      puts 'Old and new tag are the same. No change.'
      return
    end

    db_path = Config.index_db_path(config['notebook_path'])
    unless File.exist?(db_path)
      $stderr.puts 'No index found. Run zh reindex first.'
      exit 1
    end

    db = SQLite3::Database.new(db_path)
    notebook_path = File.expand_path(config['notebook_path'])
    rows = db.execute(
      "SELECT id, path FROM notes WHERE EXISTS (SELECT 1 FROM json_each(json_extract(notes.metadata, '$.tags')) WHERE value = ?)",
      [old_str]
    )
    db.close

    count = 0
    rows.each do |_id, rel_path|
      path = File.join(notebook_path, rel_path)
      next unless File.exist?(path)

      note = Note.new(path: path)
      metadata = note.metadata.dup
      tags = Array(metadata['tags']).map(&:to_s)
      next unless tags.include?(old_str)

      tags = tags.map { |t| t == old_str ? new_str : t }
      metadata['tags'] = tags
      write_note_and_reindex(path, metadata, note.body, config)
      count += 1
    end

    puts "Tag \"#{old_str}\" renamed to \"#{new_str}\" in #{count} note(s)."
    auto_commit_change(config, nil, "Rename tag '#{old_str}' to '#{new_str}'") if count > 0
  end

  def write_note_and_reindex(path, metadata, body, config)
    content = Utils.reconstruct_note_content(metadata, body)
    File.write(path, content)
    indexer = Indexer.new(config)
    indexer.index_note(Note.new(path: path))
  end

  # Auto-commits changes if git auto_commit is enabled.
  def auto_commit_change(config, paths, message)
    return unless Config.get_git_auto_commit(config)

    notebook_path = config['notebook_path']
    git = GitService.new(notebook_path)
    return unless git.repo?

    result = if paths
               git.commit(message: message, paths: paths)
             else
               git.commit(message: message, all: true)
             end

    if result[:success]
      debug_print("Auto-committed: #{message}")

      if Config.get_git_auto_push(config)
        remote = Config.get_git_remote(config)
        branch = Config.get_git_branch(config)
        push_result = git.push(remote: remote, branch: branch)
        debug_print("Auto-pushed to #{remote}/#{branch}") if push_result[:success]
      end
    else
      debug_print("Auto-commit failed: #{result[:message]}")
    end
  end

  # Prints completion candidates (subcommands and tag names) for shell completion.
  def output_completion(args)
    # Completion script passes: ruby tag.rb --completion PREV
    # PREV is the previous word (e.g. "add" or the tag name when completing note id).
    prev = args[1]

    begin
      config = Config.load(debug: false)
      notebook_path = config['notebook_path']
      db_path = notebook_path && Config.index_db_path(notebook_path)
    rescue StandardError
      puts SUBCOMMANDS.join(' ')
      return
    end

    # Completing first position after "tag" -> subcommands
    if prev.nil? || prev == 'tag' || (prev && !SUBCOMMANDS.include?(prev))
      puts SUBCOMMANDS.join(' ')
      return
    end

    unless File.exist?(db_path.to_s)
      puts ''
      return
    end

    db = SQLite3::Database.new(db_path)

    case prev
    when 'add', 'remove', 'rename'
      results = db.execute(<<-SQL)
        SELECT DISTINCT json_each.value FROM notes, json_each(json_extract(notes.metadata, '$.tags'))
        WHERE json_extract(notes.metadata, '$.tags') IS NOT NULL AND json_array_length(json_extract(notes.metadata, '$.tags')) > 0
        ORDER BY 1
      SQL
      puts results.map(&:first).compact.uniq.sort.join(' ')
    when 'list'
      puts ''
    else
      puts ''
    end

    db.close
  rescue StandardError
    puts ''
  end

  # Prints command-specific usage and options to stdout.
  def output_help
    puts <<~HELP
      Tag management: list tags, add/remove tags on notes, rename tags

      USAGE:
          zh tag [list]              List all tags with counts (default)
          zh tag add TAG NOTE_ID      Add tag to a note
          zh tag remove TAG NOTE_ID   Remove tag from a note
          zh tag rename OLD_TAG NEW_TAG   Rename a tag across all notes
          zh tags                     Same as zh tag list

      SUBCOMMANDS:
          list    List all tags with note counts (default if no subcommand)
          add     Add TAG to the note identified by NOTE_ID
          remove  Remove TAG from the note identified by NOTE_ID
          rename  Replace OLD_TAG with NEW_TAG in every note that has OLD_TAG

      OPTIONS:
          --help, -h      Show this help message
          --completion    Output shell completion candidates

      EXAMPLES:
          zh tags
          zh tag list
          zh tag add work abc12345
          zh tag remove work abc12345
          zh tag rename old-tag new-tag
    HELP
  end
end

TagCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
