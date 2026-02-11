# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'yaml'
require_relative '../lib/install_config'

class InstallConfigTest < Minitest::Test
  def setup
    @tmp = Dir.mktmpdir
    @default_path = File.join(@tmp, 'default.yaml')
    @target_path = File.join(@tmp, 'target.yaml')
    @backup_dir = File.join(@tmp, 'zh', 'backups', '20260210120000')
  end

  def teardown
    FileUtils.rm_rf(@tmp)
  end

  def test_no_user_config_writes_default
    write_yaml(@default_path, 'config_version' => '0.2.13', 'notebook_path' => '~/notes')
    refute File.exist?(@target_path)

    result = InstallConfig.run(@default_path, @target_path, '')

    assert_equal 0, result
    assert File.exist?(@target_path)
    written = YAML.load_file(@target_path)
    assert_equal '0.2.13', written['config_version']
    assert_equal '~/notes', written['notebook_path']
  end

  def test_same_major_merges_and_keeps_user_values
    write_yaml(@default_path, 'config_version' => '0.2.13', 'notebook_path' => '~/default', 'engine' => { 'date_format' => '%Y-%m-%d' })
    write_yaml(@target_path, 'config_version' => '0.2.13', 'notebook_path' => '~/my-notes', 'engine' => { 'date_format' => '%d.%m.%Y' })

    result = InstallConfig.run(@default_path, @target_path, '')

    assert_equal 0, result
    written = YAML.load_file(@target_path)
    assert_equal '0.2.13', written['config_version']
    assert_equal '~/my-notes', written['notebook_path'], 'user value should be kept'
    assert_equal '%d.%m.%Y', written.dig('engine', 'date_format'), 'user nested value should be kept'
  end

  def test_user_no_version_treated_as_zero_major_merges
    write_yaml(@default_path, 'config_version' => '0.2.13', 'notebook_path' => '~/default')
    write_yaml(@target_path, 'notebook_path' => '~/my-notes')

    result = InstallConfig.run(@default_path, @target_path, '')

    assert_equal 0, result
    written = YAML.load_file(@target_path)
    assert_equal '~/my-notes', written['notebook_path']
    assert_equal '0.2.13', written['config_version']
  end

  def test_breaking_writes_diff_and_new_to_backup_dir
    write_yaml(@default_path, 'config_version' => '1.0.0', 'notebook_path' => '~/default')
    write_yaml(@target_path, 'config_version' => '0.2.13', 'notebook_path' => '~/my-notes')
    FileUtils.mkdir_p(@backup_dir)

    result = InstallConfig.run(@default_path, @target_path, @backup_dir)

    assert_equal 0, result
    assert_equal '0.2.13', YAML.load_file(@target_path)['config_version'], 'user config should be unchanged'
    new_path = File.join(@backup_dir, 'config.yaml.new')
    diff_path = File.join(@backup_dir, 'config.yaml.diff')
    assert File.exist?(new_path), 'config.yaml.new should be written'
    assert_equal '1.0.0', YAML.load_file(new_path)['config_version']
    assert File.exist?(diff_path), 'config.yaml.diff should be written'
  end

  def test_backup_dir_under_zk_next_backups
    write_yaml(@default_path, 'config_version' => '1.0.0', 'notebook_path' => '~/default')
    write_yaml(@target_path, 'config_version' => '0.2.13', 'notebook_path' => '~/my-notes')
    FileUtils.mkdir_p(@backup_dir)
    assert @backup_dir.include?('zh') && @backup_dir.include?('backups')

    InstallConfig.run(@default_path, @target_path, @backup_dir)

    assert File.exist?(File.join(@backup_dir, 'config.yaml.new'))
    assert File.exist?(File.join(@backup_dir, 'config.yaml.diff'))
  end

  def test_missing_default_config_returns_error
    refute File.exist?(@default_path)

    result = InstallConfig.run(@default_path, @target_path, '')

    assert_equal 1, result
    refute File.exist?(@target_path)
  end

  def test_user_config_not_a_mapping_returns_error
    write_yaml(@default_path, 'config_version' => '0.2.13')
    File.write(@target_path, '--- 42') # valid YAML but not a Hash

    result = InstallConfig.run(@default_path, @target_path, '')

    assert_equal 1, result
  end

  private

  def write_yaml(path, hash)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, hash.to_yaml)
  end
end
