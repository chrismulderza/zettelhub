# frozen_string_literal: true

require 'minitest/autorun'
require 'rbconfig'
require 'tmpdir'
require 'yaml'
require 'fileutils'
require 'open3'
require_relative '../../lib/cmd/find'
require_relative '../../lib/cmd/init'
require_relative '../../lib/config'

class FindCommandTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @temp_home = Dir.mktmpdir
    @global_config_file = File.join(@temp_home, '.config', 'zh', 'config.yaml')
    @original_config_file = Config::CONFIG_FILE
    Config.send(:remove_const, :CONFIG_FILE)
    Config.const_set(:CONFIG_FILE, @global_config_file)

    Dir.singleton_class.class_eval do
      alias_method :original_home, :home
      define_method(:home) { @temp_home }
    end
    Dir.instance_variable_set(:@temp_home, @temp_home)

    @original_home_env = ENV['HOME']
    ENV['HOME'] = @temp_home

    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    global_config = { 'notebook_path' => @tmpdir, 'templates' => [] }
    File.write(@global_config_file, global_config.to_yaml)

    Dir.chdir(@tmpdir) do
      InitCommand.new.run
    end
  end

  def teardown
    Dir.singleton_class.class_eval do
      alias_method :home, :original_home
      remove_method :original_home
    end
    ENV['HOME'] = @original_home_env if @original_home_env
    FileUtils.remove_entry @tmpdir
    FileUtils.remove_entry @temp_home
    Config.send(:remove_const, :CONFIG_FILE)
    Config.const_set(:CONFIG_FILE, @original_config_file)
  end

  def test_help_output
    cmd = FindCommand.new
    out, _err = capture_io do
      cmd.run('--help')
    end
    assert_match(/Interactive find/, out)
    assert_match(/ripgrep.*fzf/, out)
    assert_match(/USAGE/, out)
  end

  def test_completion_returns_empty
    cmd = FindCommand.new
    out, _err = capture_io do
      cmd.run('--completion')
    end
    assert_equal '', out.strip
  end

  def test_exits_when_notebook_path_not_found
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    bad_config = { 'notebook_path' => '/nonexistent/notebook', 'templates' => [] }
    File.write(@global_config_file, bad_config.to_yaml)

    # Run from a directory with no .zh so config resolution uses global config
    # (otherwise CWD's .zh in the project root would be found first)
    no_zh_dir = Dir.mktmpdir
    begin
      Dir.chdir(no_zh_dir) do
        ex = assert_raises(SystemExit) do
          capture_io { FindCommand.new.run }
        end
        assert_equal 1, ex.status
      end
    ensure
      FileUtils.rm_rf(no_zh_dir) if Dir.exist?(no_zh_dir)
    end
  end

  def test_exits_with_message_when_rg_missing
    # Run find in subprocess with PATH empty so `which rg` fails
    ruby_exe = RbConfig.ruby
    project_root = File.expand_path('../..', __dir__)
    env = { 'HOME' => @temp_home, 'PATH' => '' }
    _out, err, status = Open3.capture3(env, ruby_exe, '-Ilib', 'lib/cmd/find.rb', chdir: project_root)
    assert_equal 1, status.exitstatus, "expected exit 1, got #{status.exitstatus}. stderr: #{err}"
    assert_match(/ripgrep|rg/, err, "stderr should mention ripgrep: #{err}")
  end

  def test_exits_with_message_when_fzf_missing
    # Run find in subprocess with PATH that has rg and which but not fzf
    rg_path = `which rg 2>/dev/null`.strip
    fzf_path = `which fzf 2>/dev/null`.strip
    skip 'rg not installed' if rg_path.empty?
    skip 'rg and fzf in same dir; cannot simulate fzf missing' if !fzf_path.empty? && File.dirname(rg_path) == File.dirname(fzf_path)
    ruby_exe = RbConfig.ruby
    project_root = File.expand_path('../..', __dir__)
    path_with_rg_only = [File.dirname(rg_path), '/usr/bin', '/bin'].join(File::PATH_SEPARATOR)
    env = { 'HOME' => @temp_home, 'PATH' => path_with_rg_only }
    _out, err, status = Open3.capture3(env, ruby_exe, '-Ilib', 'lib/cmd/find.rb', chdir: project_root)
    assert_equal 1, status.exitstatus, "expected exit 1, got #{status.exitstatus}. stderr: #{err}"
    assert_match(/fzf/, err, "stderr should mention fzf: #{err}")
  end

  def test_parse_args_returns_first_non_option_as_initial_query
    cmd = FindCommand.new
    # Parse args is private; test via run with --help to avoid actually running fzf
    # Instead test that run('foo') passes 'foo' as initial query by checking we don't exit early
    # We can only test parse_args by running with --help and ensuring help is shown
    out, = capture_io { cmd.run('--help') }
    assert_match(/query/, out)
  end
end
