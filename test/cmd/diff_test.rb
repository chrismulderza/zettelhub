# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../../lib/cmd/diff'
require_relative '../../lib/git_service'
require_relative '../../lib/indexer'
require_relative '../../lib/models/note'

# Tests for DiffCommand.
class DiffCommandTest < Minitest::Test
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
    @note_path = File.join(@tmpdir, 'abc12345-test-note.md')
    File.write(@note_path, @note_content)
    @git.commit(message: 'Add test note', all: true)

    # Index the note
    config = { 'notebook_path' => @tmpdir }
    indexer = Indexer.new(config)
    indexer.index_note(Note.new(path: @note_path))
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  def test_help_output
    cmd = DiffCommand.new
    assert_output(/USAGE/) { cmd.run('--help') }
  end

  def test_help_with_short_flag
    cmd = DiffCommand.new
    assert_output(/USAGE/) { cmd.run('-h') }
  end

  def test_completion_output
    cmd = DiffCommand.new
    assert_output(/--staged/) { cmd.run('--completion') }
  end

  def test_diff_requires_note_ref
    cmd = DiffCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run }
    end
  end

  def test_diff_not_found_exits
    cmd = DiffCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run('nonexistent') }
    end
  end

  def test_diff_no_changes
    cmd = DiffCommand.new
    out, = capture_io { cmd.run('abc12345', '--no-color') }
    assert_includes out, 'No changes'
  end

  def test_diff_shows_changes
    # Modify the file
    File.write(@note_path, @note_content + "\nModified content")

    cmd = DiffCommand.new
    out, = capture_io { cmd.run('abc12345', '--no-color') }
    assert_includes out, 'Modified content'
  end

  def test_diff_by_path
    # Modify the file
    File.write(@note_path, @note_content + "\nPath change")

    cmd = DiffCommand.new
    out, = capture_io { cmd.run('abc12345-test-note.md', '--no-color') }
    assert_includes out, 'Path change'
  end

  def test_diff_staged_flag
    # Stage a change
    File.write(@note_path, @note_content + "\nStaged change")
    system('git', '-C', @tmpdir, 'add', 'abc12345-test-note.md')

    cmd = DiffCommand.new
    out, = capture_io { cmd.run('abc12345', '--staged', '--no-color') }
    assert_includes out, 'Staged change'
  end

  def test_diff_no_color_flag
    # Modify the file
    File.write(@note_path, @note_content + "\nNo color change")

    cmd = DiffCommand.new
    out, = capture_io { cmd.run('abc12345', '--no-color') }
    # Should not contain ANSI escape codes
    refute_match(/\e\[/, out)
  end

  def test_diff_not_repo_error
    # Remove .git to simulate non-repo
    FileUtils.rm_rf(File.join(@tmpdir, '.git'))

    cmd = DiffCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run('abc12345') }
    end
  end

  def test_diff_at_specific_commit
    # Make another commit
    File.write(@note_path, @note_content + "\nSecond version")
    @git.commit(message: 'Update note', all: true)

    commits = @git.log(path: @note_path)
    first_commit = commits.last[:hash][0, 7]

    cmd = DiffCommand.new
    out, = capture_io { cmd.run('abc12345', first_commit, '--no-color') }
    # Should show something about the commit
    assert_match(/Commit:|added|Content/, out)
  end
end
