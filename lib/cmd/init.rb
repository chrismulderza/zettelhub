#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require_relative '../config'

# Init command for initializing a new notebook
class InitCommand
  # Handles --completion and --help; initializes notebook directory and .zh structure.
  def run(*args)
    return output_completion if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    zh_dir = Config::ZH_DIRNAME
    Dir.mkdir(zh_dir) unless Dir.exist?(zh_dir)

    config_file = File.join(zh_dir, 'config.yaml')
    if File.exist?(config_file)
      puts 'Notebook already initialized'
    else
      config = {
        'notebook_path' => Dir.pwd,
        'engine' => {
          'date_format' => Config.default_engine_date_format,
          'slugify_replacement' => Config.default_engine_slugify_replacement,
          'default_alias' => Config.default_engine_default_alias,
          'db_result_delimiter' => Config.default_engine_db_result_delimiter
        }
      }
      File.write(config_file, config.to_yaml)
      puts "Initialized notebook in #{Dir.pwd}"
      puts 'Created .zh/config.yaml'
    end
  end

  private

  # Prints completion candidates for shell completion (empty for init).
  def output_completion
    puts '--help -h'
  end

  # Prints command-specific usage and options to stdout.
  def output_help
    puts <<~HELP
      Initialize a new notebook directory

      USAGE:
          zh init

      DESCRIPTION:
          Creates a .zh directory in the current directory and writes a default
          config.yaml with notebook_path and engine settings. Idempotent: if
          .zh/config.yaml already exists, prints "Notebook already initialized".

      OPTIONS:
          --help, -h     Show this help message
          --completion   Output shell completion candidates (empty for this command)

      EXAMPLES:
          zh init       Initialize notebook in current directory
    HELP
  end
end

InitCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
