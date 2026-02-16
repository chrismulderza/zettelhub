#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require_relative '../config'
require_relative '../theme'
require_relative '../debug'

# Theme command for managing color themes across CLI tools.
# Provides: list, preview, export, apply subcommands.
class ThemeCommand
  include Debug

  SUBCOMMANDS = %w[list preview export apply current].freeze

  # Main entry point.
  def run(*args)
    return output_completion if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    subcommand = args.shift || 'list'

    case subcommand
    when 'list'
      run_list
    when 'preview'
      run_preview(args)
    when 'export'
      run_export(args)
    when 'apply'
      run_apply(args)
    when 'current'
      run_current
    else
      # Treat as theme name for preview
      run_preview([subcommand] + args)
    end
  end

  private

  # List all available themes.
  def run_list
    themes = Theme.list

    puts "Available themes:"
    puts ""

    themes.each do |name|
      begin
        data = Theme.load(name, debug: debug?)
        description = data['description'] || ''
        puts "  #{name.ljust(15)} #{description}"
      rescue StandardError => e
        debug_print("Error loading theme #{name}: #{e.message}")
        puts "  #{name.ljust(15)} (error loading)"
      end
    end

    puts ""
    puts "Use 'zh theme preview <name>' to see colors"
    puts "Use 'zh theme export <name>' to generate shell config"
  end

  # Preview a theme's colors in terminal.
  def run_preview(args)
    theme_name = args.first || current_theme_name
    
    begin
      data = Theme.load(theme_name, debug: debug?)
      puts Theme.preview(data)
    rescue StandardError => e
      $stderr.puts "Error: #{e.message}"
      exit 1
    end
  end

  # Export theme as shell environment variables.
  def run_export(args)
    # Parse options
    format = :bash
    theme_name = nil

    args.each do |arg|
      case arg
      when '--fish'
        format = :fish
      when '--zsh'
        format = :zsh
      when '--bash'
        format = :bash
      else
        theme_name = arg unless arg.start_with?('-')
      end
    end

    theme_name ||= current_theme_name

    begin
      data = Theme.load(theme_name, debug: debug?)
      puts Theme.export_shell(data, format: format)
    rescue StandardError => e
      $stderr.puts "Error: #{e.message}"
      exit 1
    end
  end

  # Apply theme by writing config files (glow style, etc.).
  def run_apply(args)
    theme_name = args.find { |a| !a.start_with?('-') } || current_theme_name
    output_dir = File.join(Dir.home, '.config', 'zh', 'themes')

    begin
      data = Theme.load(theme_name, debug: debug?)
      written = Theme.apply(data, output_dir: output_dir)

      puts "Applied theme: #{theme_name}"
      puts ""
      written.each do |tool, path|
        puts "  #{tool}: #{path}"
      end
      puts ""
      puts "Add to your shell profile:"
      puts "  eval \"$(zh theme export #{theme_name})\""
    rescue StandardError => e
      $stderr.puts "Error: #{e.message}"
      exit 1
    end
  end

  # Show current theme from config.
  def run_current
    name = current_theme_name
    puts "Current theme: #{name}"

    begin
      data = Theme.load(name, debug: debug?)
      description = data['description'] || ''
      puts "Description: #{description}" unless description.empty?
    rescue StandardError => e
      debug_print("Error loading theme: #{e.message}")
    end
  end

  # Get current theme name from config.
  def current_theme_name
    begin
      config = Config.load(debug: debug?)
      config.dig('theme', 'name') || config['theme'] || Theme::DEFAULT_THEME
    rescue StandardError
      Theme::DEFAULT_THEME
    end
  end

  # Prints completion candidates.
  def output_completion
    themes = Theme.list.join(' ') rescue ''
    puts "#{SUBCOMMANDS.join(' ')} #{themes} --bash --zsh --fish --help -h"
  end

  # Prints command-specific help.
  def output_help
    puts <<~HELP
      Manage color themes for CLI tools (gum, fzf, bat, glow)

      USAGE:
          zh theme [SUBCOMMAND] [OPTIONS]

      SUBCOMMANDS:
          list                List available themes
          current             Show current theme from config
          preview [NAME]      Preview theme colors in terminal
          export [NAME]       Output shell environment variables
          apply [NAME]        Write config files (glow style, etc.)

      OPTIONS:
          --bash              Export for bash/zsh (default)
          --zsh               Export for zsh (same as bash)
          --fish              Export for fish shell
          --help, -h          Show this help message

      CONFIGURATION:
          Set theme in config.yaml:
            theme: nord

          Or with full palette customization:
            theme:
              name: custom
              palette:
                accent: "#88C0D0"
                # ... other colors

      AVAILABLE THEMES:
          nord            Arctic, north-bluish palette
          dracula         Dark theme with vibrant colors
          tokyo-night     Clean dark theme, Tokyo lights
          gruvbox         Retro groove, warm tones
          catppuccin      Soothing pastel (Mocha)

      EXAMPLES:
          zh theme list
          zh theme preview nord
          zh theme export dracula
          zh theme export --fish tokyo-night
          zh theme apply gruvbox

      SHELL INTEGRATION:
          Add to ~/.bashrc or ~/.zshrc:
            eval "$(zh theme export)"

          For fish, add to ~/.config/fish/config.fish:
            zh theme export --fish | source
    HELP
  end
end

ThemeCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
