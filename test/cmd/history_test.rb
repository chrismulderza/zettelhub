# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require_relative '../../lib/cmd/history'
require_relative '../../lib/git_service'
require_relative '../../lib/indexer'
require_relative '../../lib/models/note'

# Tests for HistoryCommand.
class HistoryCommandTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@tmpdir)

    # Create .zh directory and minimal config
    FileUtils.mkdir_p('.zh')
    File.write('.zh/config.yaml', "notebook_path: #{@tmpdir}")

    # Initialize git repo
    @git = GitService.new(@tmpdir)
    @git.init

    # Create a test note
    @note_content = <<~NOTE
      ---
      id: "abc12345"
      title: "Test Note"
      date: "2025-02-10"
      tags: []
      ---
      # Test Note
      
      Content here.
    NOTE
    File.write('abc12345-test-note.md', @note_content)
    @git.commit(message: 'Add test note', all: true)

    # Index the note
    config = { 'notebook_path' => @tmpdir }
    indexer = Indexer.new(config)
    indexer.index_note(Note.new(path: File.join(@tmpdir, 'abc12345-test-note.md')))
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  def test_help_output
    cmd = HistoryCommand.new
    assert_output(/USAGE/) { cmd.run('--help') }
  end

  def test_help_with_short_flag
    cmd = HistoryCommand.new
    assert_output(/USAGE/) { cmd.run('-h') }
  end

  def test_completion_output
    cmd = HistoryCommand.new
    assert_output(/--limit/) { cmd.run('--completion') }
  end

  def test_history_requires_note_ref
    cmd = HistoryCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run }
    end
  end

  def test_history_not_found_exits
    cmd = HistoryCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run('nonexistent') }
    end
  end

  def test_history_list_format
    cmd = HistoryCommand.new
    out, = capture_io { cmd.run('abc12345', '--list') }
    assert_includes out, 'Add test note'
  end

  def test_history_table_format
    cmd = HistoryCommand.new
    out, = capture_io { cmd.run('abc12345', '--table') }
    assert_includes out, 'COMMIT'
    assert_includes out, 'DATE'
    assert_includes out, 'AUTHOR'
  end

  def test_history_json_format
    cmd = HistoryCommand.new
    out, = capture_io { cmd.run('abc12345', '--json') }
    parsed = JSON.parse(out)
    assert_kind_of Array, parsed
    assert_equal 1, parsed.length
    assert_equal 'Add test note', parsed[0]['message']
  end

  def test_history_with_limit
    # Create more commits
    File.write('abc12345-test-note.md', @note_content + "\nUpdate 1")
    @git.commit(message: 'Update 1', all: true)

    File.write('abc12345-test-note.md', @note_content + "\nUpdate 2")
    @git.commit(message: 'Update 2', all: true)

    cmd = HistoryCommand.new
    out, = capture_io { cmd.run('abc12345', '--list', '--limit', '1') }
    # Should only show 1 commit
    lines = out.strip.split("\n")
    assert_equal 1, lines.length
  end

  def test_history_by_path
    cmd = HistoryCommand.new
    out, = capture_io { cmd.run('abc12345-test-note.md', '--list') }
    assert_includes out, 'Add test note'
  end

  def test_history_not_repo_error
    # Remove .git to simulate non-repo
    FileUtils.rm_rf(File.join(@tmpdir, '.git'))

    cmd = HistoryCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run('abc12345', '--list') }
    end
  end
end
