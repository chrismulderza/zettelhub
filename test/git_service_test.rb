# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/git_service'

# Tests for GitService git wrapper class.
class GitServiceTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @git = GitService.new(@tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_repo_false_when_not_initialized
    refute @git.repo?
  end

  def test_init_creates_git_repo
    result = @git.init
    assert result[:success]
    assert @git.repo?
    assert File.exist?(File.join(@tmpdir, '.git'))
  end

  def test_init_creates_gitignore
    @git.init
    gitignore_path = File.join(@tmpdir, '.gitignore')
    assert File.exist?(gitignore_path)
    content = File.read(gitignore_path)
    assert_includes content, '.zh/'
  end

  def test_init_fails_if_already_repo
    @git.init
    result = @git.init
    refute result[:success]
    assert_includes result[:message], 'Already a git repository'
  end

  def test_status_empty_when_not_repo
    status = @git.status
    assert_equal [], status[:modified]
    assert_equal [], status[:added]
    assert_equal [], status[:deleted]
    assert_equal [], status[:untracked]
  end

  def test_status_shows_untracked_files
    @git.init
    File.write(File.join(@tmpdir, 'test.md'), '# Test')
    
    status = @git.status
    assert_includes status[:untracked], 'test.md'
  end

  def test_status_shows_modified_files
    @git.init
    file_path = File.join(@tmpdir, 'test.md')
    File.write(file_path, '# Test')
    
    # Stage and commit
    system('git', '-C', @tmpdir, 'add', 'test.md')
    system('git', '-C', @tmpdir, 'commit', '-m', 'Initial')
    
    # Modify
    File.write(file_path, '# Modified')
    
    status = @git.status
    assert_includes status[:modified], 'test.md'
  end

  def test_commit_without_repo_fails
    result = @git.commit(message: 'Test')
    refute result[:success]
    assert_includes result[:message], 'Not a git repository'
  end

  def test_commit_with_all_flag
    @git.init
    File.write(File.join(@tmpdir, 'test.md'), '# Test')
    
    result = @git.commit(message: 'Add test', all: true)
    assert result[:success]
    
    status = @git.status
    assert_empty status[:untracked]
  end

  def test_commit_specific_paths
    @git.init
    File.write(File.join(@tmpdir, 'a.md'), '# A')
    File.write(File.join(@tmpdir, 'b.md'), '# B')
    
    result = @git.commit(message: 'Add a', paths: [File.join(@tmpdir, 'a.md')])
    assert result[:success]
    
    status = @git.status
    assert_includes status[:untracked], 'b.md'
    refute_includes status[:untracked], 'a.md'
  end

  def test_log_empty_when_no_commits
    @git.init
    commits = @git.log
    assert_empty commits
  end

  def test_log_returns_commits
    @git.init
    File.write(File.join(@tmpdir, 'test.md'), '# Test')
    @git.commit(message: 'First commit', all: true)
    
    commits = @git.log
    assert_equal 1, commits.length
    assert_equal 'First commit', commits[0][:message]
    refute_nil commits[0][:hash]
    refute_nil commits[0][:date]
    refute_nil commits[0][:author]
  end

  def test_log_with_limit
    @git.init
    3.times do |i|
      File.write(File.join(@tmpdir, "test#{i}.md"), "# Test #{i}")
      @git.commit(message: "Commit #{i}", all: true)
    end
    
    commits = @git.log(limit: 2)
    assert_equal 2, commits.length
  end

  def test_log_for_specific_file
    @git.init
    File.write(File.join(@tmpdir, 'a.md'), '# A')
    @git.commit(message: 'Add a', all: true)
    
    File.write(File.join(@tmpdir, 'b.md'), '# B')
    @git.commit(message: 'Add b', all: true)
    
    commits = @git.log(path: File.join(@tmpdir, 'a.md'))
    assert_equal 1, commits.length
    assert_equal 'Add a', commits[0][:message]
  end

  def test_diff_empty_when_no_changes
    @git.init
    File.write(File.join(@tmpdir, 'test.md'), '# Test')
    @git.commit(message: 'Initial', all: true)
    
    diff = @git.diff
    assert_empty diff.strip
  end

  def test_diff_shows_changes
    @git.init
    file_path = File.join(@tmpdir, 'test.md')
    File.write(file_path, '# Test')
    @git.commit(message: 'Initial', all: true)
    
    File.write(file_path, '# Modified')
    
    diff = @git.diff
    assert_includes diff, 'Modified'
  end

  def test_show_returns_file_at_commit
    @git.init
    file_path = File.join(@tmpdir, 'test.md')
    File.write(file_path, '# Original')
    @git.commit(message: 'Initial', all: true)
    
    commits = @git.log
    commit_hash = commits[0][:hash]
    
    File.write(file_path, '# Changed')
    @git.commit(message: 'Change', all: true)
    
    content = @git.show(commit: commit_hash, path: file_path)
    assert_equal '# Original', content.strip
  end

  def test_checkout_restores_file
    @git.init
    file_path = File.join(@tmpdir, 'test.md')
    File.write(file_path, '# Original')
    @git.commit(message: 'Initial', all: true)
    
    commits = @git.log
    commit_hash = commits[0][:hash]
    
    File.write(file_path, '# Changed')
    @git.commit(message: 'Change', all: true)
    
    result = @git.checkout(path: file_path, commit: commit_hash)
    assert result[:success]
    
    content = File.read(file_path)
    assert_equal '# Original', content.strip
  end

  def test_current_branch
    @git.init
    File.write(File.join(@tmpdir, 'test.md'), '# Test')
    @git.commit(message: 'Initial', all: true)
    
    branch = @git.current_branch
    assert_includes ['main', 'master'], branch
  end

  def test_dirty_false_when_clean
    @git.init
    File.write(File.join(@tmpdir, 'test.md'), '# Test')
    @git.commit(message: 'Initial', all: true)
    
    refute @git.dirty?
  end

  def test_dirty_true_when_modified
    @git.init
    file_path = File.join(@tmpdir, 'test.md')
    File.write(file_path, '# Test')
    @git.commit(message: 'Initial', all: true)
    
    File.write(file_path, '# Modified')
    
    assert @git.dirty?
  end

  def test_dirty_true_when_untracked
    @git.init
    File.write(File.join(@tmpdir, 'test.md'), '# Test')
    @git.commit(message: 'Initial', all: true)
    
    File.write(File.join(@tmpdir, 'new.md'), '# New')
    
    assert @git.dirty?
  end

  def test_push_without_remote_fails
    @git.init
    File.write(File.join(@tmpdir, 'test.md'), '# Test')
    @git.commit(message: 'Initial', all: true)
    
    result = @git.push
    refute result[:success]
    assert_includes result[:message], 'not found'
  end

  def test_pull_without_remote_fails
    @git.init
    
    result = @git.pull
    refute result[:success]
    assert_includes result[:message], 'not found'
  end
end
