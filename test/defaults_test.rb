# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/config'

# Tests for config path constants (Config is the single source of truth for global config paths).
# Former Defaults class has been removed; Config holds CONFIG_DIR and CONFIG_FILE.
class DefaultsTest < Minitest::Test
  def test_config_dir_and_file_are_defined
    assert Config.const_defined?(:CONFIG_DIR)
    assert Config.const_defined?(:CONFIG_FILE)
  end

  def test_config_path_has_expected_structure
    # CONFIG_DIR is evaluated at load time with the original HOME
    assert Config::CONFIG_DIR.include?('.config')
    assert Config::CONFIG_DIR.include?('zh')
    assert Config::CONFIG_FILE.include?('.config')
    assert Config::CONFIG_FILE.include?('zh')
    assert Config::CONFIG_FILE.include?('config.yaml')
  end

  def test_config_dir_at_runtime_respects_env_home
    # config_dir_at_runtime uses ENV['HOME'] at call time
    assert Config.respond_to?(:config_dir_at_runtime)
    dir = Config.config_dir_at_runtime
    assert dir.include?('.config')
    assert dir.include?('zh')
  end

  def test_config_file_ends_with_config_yaml
    assert Config::CONFIG_FILE.end_with?('config.yaml')
    assert_equal 'config.yaml', File.basename(Config::CONFIG_FILE)
  end
end
