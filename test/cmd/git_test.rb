# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../../lib/cmd/git'

# Tests for GitCommand.
class GitCommandTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @original_dir = Dir.pwd
    Dir.chdir(@tmpdir)

    # Create .zh directory and minimal config
    FileUtils.mkdir_p('.zh')
    File.write('.zh/config.yaml', "notebook_path: #{@tmpdir}")
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmpdir)
  end

  def test_help_output
    cmd = GitCommand.new
    assert_output(/USAGE/) { cmd.run('--help') }
  end

  def test_help_with_short_flag
    cmd = GitCommand.new
    assert_output(/USAGE/) { cmd.run('-h') }
  end

  def test_help_with_no_args
    cmd = GitCommand.new
    assert_output(/USAGE/) { cmd.run }
  end

  def test_completion_output
    cmd = GitCommand.new
    assert_output(/init status commit sync/) { cmd.run('--completion') }
  end

  def test_init_creates_repo
    cmd = GitCommand.new
    assert_output(/Initialized git repository/) { cmd.run('init') }
    assert File.exist?(File.join(@tmpdir, '.git'))
  end

  def test_init_creates_gitignore
    cmd = GitCommand.new
    cmd.run('init')
    gitignore_path = File.join(@tmpdir, '.gitignore')
    assert File.exist?(gitignore_path)
    content = File.read(gitignore_path)
    assert_includes content, '.zh/'
  end

  def test_init_help
    cmd = GitCommand.new
    assert_output(/Initialize a git repository/) { cmd.run('init', '--help') }
  end

  def test_status_not_repo_error
    cmd = GitCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run('status') }
    end
  end

  def test_status_clean_repo
    cmd = GitCommand.new
    cmd.run('init')
    # Commit the .gitignore to have a clean repo
    system('git', '-C', @tmpdir, 'add', '.gitignore')
    system('git', '-C', @tmpdir, 'commit', '-m', 'Initial')

    out, = capture_io { cmd.run('status') }
    assert_includes out, 'Nothing to commit'
  end

  def test_status_shows_untracked
    cmd = GitCommand.new
    cmd.run('init')
    File.write('test.md', "---\ntitle: Test\n---\n# Test")

    out, = capture_io { cmd.run('status') }
    assert_includes out, 'Untracked files'
    assert_includes out, 'test.md'
  end

  def test_status_help
    cmd = GitCommand.new
    assert_output(/Show the status/) { cmd.run('status', '--help') }
  end

  def test_commit_not_repo_error
    cmd = GitCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run('commit', '-m', 'Test') }
    end
  end

  def test_commit_with_message
    cmd = GitCommand.new
    cmd.run('init')
    File.write('test.md', "---\ntitle: Test\n---\n# Test")

    out, = capture_io { cmd.run('commit', '--all', '-m', 'Add test') }
    assert_includes out, 'committed'
  end

  def test_commit_auto_message
    cmd = GitCommand.new
    cmd.run('init')
    File.write('test.md', "---\ntitle: Test\n---\n# Test")

    out, = capture_io { cmd.run('commit', '--all') }
    assert_includes out, 'committed'
  end

  def test_commit_help
    cmd = GitCommand.new
    assert_output(/Commit changes/) { cmd.run('commit', '--help') }
  end

  def test_sync_not_repo_error
    cmd = GitCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run('sync') }
    end
  end

  def test_sync_help
    cmd = GitCommand.new
    assert_output(/Sync with remote/) { cmd.run('sync', '--help') }
  end

  def test_unknown_subcommand_error
    cmd = GitCommand.new
    assert_raises(SystemExit) do
      capture_io { cmd.run('unknown') }
    end
  end
end
