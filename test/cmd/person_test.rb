# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../../lib/cmd/person'

# Tests for PersonCommand completion functionality.
class PersonCommandTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @temp_home = Dir.mktmpdir
    @global_config_file = File.join(@temp_home, '.config', 'zh', 'config.yaml')

    # Create minimal config
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    global_config = { 'notebook_path' => @tmpdir }
    File.write(@global_config_file, global_config.to_yaml)

    # Setup .zh directory
    FileUtils.mkdir_p(File.join(@tmpdir, '.zh'))

    @original_home_env = ENV['HOME']
    ENV['HOME'] = @temp_home
  end

  def teardown
    ENV['HOME'] = @original_home_env if @original_home_env
    FileUtils.remove_entry @tmpdir if Dir.exist?(@tmpdir)
    FileUtils.remove_entry @temp_home if Dir.exist?(@temp_home)
  end

  def test_completion_default
    cmd = PersonCommand.new
    out, = capture_io { cmd.run('--completion') }
    assert_includes out, 'add'
    assert_includes out, 'list'
    assert_includes out, 'export'
    assert_includes out, 'browse'
  end

  def test_completion_output_option
    cmd = PersonCommand.new
    out, = capture_io { cmd.run('--completion', '--output') }
    assert_equal '__FILE__', out.strip, 'Completion for --output should return __FILE__ signal'
  end

  def test_completion_short_output_option
    cmd = PersonCommand.new
    out, = capture_io { cmd.run('--completion', '-o') }
    assert_equal '__FILE__', out.strip, 'Completion for -o should return __FILE__ signal'
  end

  private

  def capture_io
    require 'stringio'
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    [$stdout.string, $stderr.string]
  ensure
    $stdout = old_stdout
    $stderr = old_stderr
  end
end
