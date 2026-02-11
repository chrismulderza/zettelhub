require 'minitest/autorun'
require 'tmpdir'
require 'yaml'
require_relative '../../lib/cmd/init'

class InitCommandTest < Minitest::Test
  def test_run_initializes_notebook
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        InitCommand.new.run
        assert Dir.exist?('.zh'), '.zh directory should be created'
        assert File.exist?('.zh/config.yaml'), 'config.yaml should be created'
        config = YAML.load_file('.zh/config.yaml')
        assert_equal Dir.pwd, config['notebook_path']
        assert config['engine'].is_a?(Hash), 'engine section should be present'
        # Templates are discovered from .zh/templates and global dirs, not stored in config
        refute config.key?('templates'), 'config should not contain templates key'
      end
    end
  end

  def test_run_already_initialized
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        InitCommand.new.run
        # Running again should not error
        output = capture_io { InitCommand.new.run }.first
        assert_includes output, 'Notebook already initialized'
        assert Dir.exist?('.zh')
      end
    end
  end

  def test_completion_output
    cmd = InitCommand.new
    output = capture_io { cmd.run('--completion') }.first
    assert_equal '', output.strip, 'Completion should return empty string'
  end

  def test_run_creates_correct_config_structure
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        InitCommand.new.run
        config = YAML.load_file('.zh/config.yaml')
        assert config.is_a?(Hash)
        assert_equal Dir.pwd, config['notebook_path']
        assert config['engine'].is_a?(Hash)
        assert config['engine'].key?('date_format')
        assert config['engine'].key?('slugify_replacement')
        assert config['engine'].key?('default_alias')
        refute config.key?('templates')
      end
    end
  end

  def test_run_preserves_existing_config_when_already_initialized
    Dir.mktmpdir do |tmpdir|
      Dir.chdir(tmpdir) do
        InitCommand.new.run
        # Modify config
        config = YAML.load_file('.zh/config.yaml')
        config['custom_key'] = 'custom_value'
        File.write('.zh/config.yaml', config.to_yaml)
        
        # Run init again
        InitCommand.new.run
        
        # Config should still have custom key
        config_after = YAML.load_file('.zh/config.yaml')
        assert_equal 'custom_value', config_after['custom_key']
      end
    end
  end

  private

  def capture_io
    require 'stringio'
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    [$stdout.string, '']
  ensure
    $stdout = old_stdout
  end
end
