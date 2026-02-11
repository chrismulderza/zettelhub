# frozen_string_literal: true

require 'yaml'
require 'shellwords'
require_relative 'utils'
require_relative 'debug'

# Handles config install/upgrade: merge user config with defaults or write diff on breaking change.
# Invoked by make install. Uses semantic versioning (major = breaking); only major increase
# triggers diff instead of overwrite.
module InstallConfig
  include Debug

  # Entry point: loads default and target config, writes default or merged config, or writes diff on breaking change. Returns exit code.
  def self.run(default_path, target_path, backup_dir)
    runner = Object.new.extend(InstallConfig)
    runner.run(default_path, target_path, backup_dir)
  end

  # Performs install/merge/diff; called by self.run.
  def run(default_path, target_path, backup_dir)
    default_path = File.expand_path(default_path)
    target_path = File.expand_path(target_path)
    backup_dir = backup_dir.to_s.strip
    backup_dir = File.expand_path(backup_dir) if backup_dir != ''

    unless File.exist?(default_path)
      $stderr.puts "Error: default config not found: #{default_path}"
      return 1
    end

    default_config = load_yaml_file(default_path)
    unless default_config.is_a?(Hash)
      $stderr.puts "Error: invalid default config (not a YAML mapping): #{default_path}"
      return 1
    end

    debug_print("install_config: default=#{default_path} target=#{target_path} backup_dir=#{backup_dir}")

    unless File.exist?(target_path)
      write_default(target_path, default_config)
      debug_print("install_config: no existing config, wrote default to #{target_path}")
      return 0
    end

    user_config = load_yaml_file(target_path)
    unless user_config.is_a?(Hash)
      $stderr.puts "Error: invalid user config (not a YAML mapping): #{target_path}"
      return 1
    end

    bundled_major = major_version(config_version_from(default_config))
    user_major = major_version(config_version_from(user_config))

    debug_print("install_config: bundled_major=#{bundled_major} user_major=#{user_major}")

    if bundled_major > user_major
      write_breaking_diff(target_path, default_path, default_config, backup_dir)
      return 0
    end

    merged = Utils.deep_merge(default_config, user_config)
    merged['config_version'] = default_config['config_version'] if default_config.key?('config_version')
    write_merged(target_path, merged)
    debug_print("install_config: merged config written to #{target_path}")
    0
  end

  private

  # Loads and returns YAML as Hash; returns nil on error.
  def load_yaml_file(path)
    YAML.load_file(path)
  rescue Psych::SyntaxError => e
    $stderr.puts "Error: YAML syntax error in #{path}: #{e.message}"
    nil
  end

  # Returns config_version value from config hash (or '0.0.0' if missing).
  def config_version_from(config)
    v = config['config_version']
    return '0.0.0' if v.nil? || v.to_s.strip.empty?
    v.to_s.strip
  end

  # Returns major version integer from semantic version string.
  def major_version(version_string)
    version_string.split('.').first.to_i
  end

  # Writes default config to target path.
  def write_default(target_path, default_config)
    File.write(target_path, default_config.to_yaml)
  end

  # Writes merged config to target path.
  def write_merged(target_path, merged)
    File.write(target_path, merged.to_yaml)
  end

  # Writes config.yaml.new and config.yaml.diff into backup_dir and prints message.
  def write_breaking_diff(user_path, default_path, _default_config, backup_dir)
    if backup_dir.nil? || backup_dir.empty? || !File.directory?(backup_dir)
      $stderr.puts "Error: backup directory not present; cannot write breaking-change diff."
      return
    end

    new_path = File.join(backup_dir, 'config.yaml.new')
    diff_path = File.join(backup_dir, 'config.yaml.diff')

    File.write(new_path, File.read(default_path))

    diff_cmd = "diff -u #{Shellwords.escape(user_path)} #{Shellwords.escape(default_path)}"
    diff_out = `#{diff_cmd} 2>/dev/null`
    File.write(diff_path, diff_out) if diff_out

    $stderr.puts "Config has breaking changes (bundled major > your config version)."
    $stderr.puts "Backup and diff written to: #{backup_dir}"
    $stderr.puts "Inspect config.yaml.diff and merge manually; config.yaml.new is the new default."
    debug_print("install_config: wrote config.yaml.new and config.yaml.diff to #{backup_dir}")
  end
end

# Script entrypoint: args are default_config target_config [backup_dir]
if $PROGRAM_NAME == __FILE__
  default_path = ARGV[0]
  target_path = ARGV[1]
  backup_dir = ARGV[2] || ''
  unless default_path && target_path
    $stderr.puts "Usage: #{$PROGRAM_NAME} <default_config> <target_config> [backup_dir]"
    exit 1
  end
  exit InstallConfig.run(default_path, target_path, backup_dir)
end
