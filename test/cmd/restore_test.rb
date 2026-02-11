# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../../lib/cmd/restore'
require_relative '../../lib/git_service'
require_relative '../../lib/indexer'
require_relative '../../lib/models/note'

# Tests for RestoreCommand.
class RestoreCommandTest < Minitest::Test
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

    # Create a test note - version 1
    @original_content = <<~NOTE
      ---
      id: "abc12345"
      title: "Test Note"
      date: "2025-02-10"
      tags: []
      ---
      # Test Note
      
      Original content.
    NOTE
    @note_path = File.join(@tmpdir, 'abc12345-test-note.md')
    File.write(@note_path, @original_content)
    @git.commit(message: 'Add test note', all: true)

    # Get the original commit hash
    commits = @git.log
    @original_commit = commits[0][:hash][0, 7]

    # Update the note - version 2
    @updated_content = @original_content.sub('Original content', 'Updated content')
    File.write(@note_path, @updated_content)
    @git.commit(message: 'Update note', all: true)

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
    cmd = RestoreCommand.new
    assert_output(/USAGE/) { cmd.run('--help') }
  end

  def test_help_with_short_flag
    cmd = RestoreCommand.new
    assert_output(/USAGE/) { cmd.run('-h') }
  end

  def test_completion_output
    cmd = RestoreCommand.new
    assert_output(/--preview/) { cmd.run('--completion') }
  end

  def test_restore_requires_note_ref
    cmd = RestoreCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run }
    end
  end

  def test_restore_requires_commit
    cmd = RestoreCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run('abc12345') }
    end
  end

  def test_restore_note_not_found_exits
    cmd = RestoreCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run('nonexistent', @original_commit) }
    end
  end

  def test_restore_invalid_commit_exits
    cmd = RestoreCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run('abc12345', 'deadbeef') }
    end
  end

  def test_restore_preview_mode
    cmd = RestoreCommand.new
    out, = capture_io { cmd.run('abc12345', @original_commit, '--preview') }
    assert_includes out, 'Preview'
    # Should not have changed the file
    current_content = File.read(@note_path)
    assert_includes current_content, 'Updated content'
  end

  def test_restore_performs_restore
    cmd = RestoreCommand.new
    out, = capture_io { cmd.run('abc12345', @original_commit) }
    assert_includes out, 'Restored'

    # Check file was restored
    current_content = File.read(@note_path)
    assert_includes current_content, 'Original content'
  end

  def test_restore_by_path
    cmd = RestoreCommand.new
    out, = capture_io { cmd.run('abc12345-test-note.md', @original_commit) }
    assert_includes out, 'Restored'

    current_content = File.read(@note_path)
    assert_includes current_content, 'Original content'
  end

  def test_restore_not_repo_error
    # Remove .git to simulate non-repo
    FileUtils.rm_rf(File.join(@tmpdir, '.git'))

    cmd = RestoreCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run('abc12345', @original_commit) }
    end
  end

  def test_restore_suggests_commit
    cmd = RestoreCommand.new
    out, = capture_io { cmd.run('abc12345', @original_commit) }
    assert_includes out, 'zh git commit'
  end
end
