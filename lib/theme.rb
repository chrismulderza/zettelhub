# frozen_string_literal: true

require 'yaml'
require 'json'
require 'erb'

# Theme module for unified color theming across CLI tools.
# Provides a single palette definition that generates tool-specific configurations
# for gum, fzf, bat, glow, and ripgrep.
module Theme
  # Directory containing bundled theme presets
  THEMES_DIR = File.join(__dir__, 'themes')

  # Default theme if none specified
  DEFAULT_THEME = 'nord'

  # Required palette keys for a valid theme
  REQUIRED_KEYS = %w[
    bg bg_highlight bg_selection
    fg fg_muted
    accent accent_secondary
    success warning error info
    match comment
  ].freeze

  # Load a theme palette by name.
  # Searches: user themes (~/.config/zh/themes/), then bundled themes.
  # Returns: Hash with palette colors
  def self.load(theme_name, debug: false)
    theme_name ||= DEFAULT_THEME
    theme_file = find_theme_file(theme_name, debug: debug)

    unless theme_file
      $stderr.puts "[DEBUG] Theme '#{theme_name}' not found, using default" if debug
      theme_file = find_theme_file(DEFAULT_THEME, debug: debug)
    end

    unless theme_file
      raise "Theme not found: #{theme_name}"
    end

    $stderr.puts "[DEBUG] Loading theme from: #{theme_file}" if debug
    data = YAML.load_file(theme_file)
    validate_palette!(data['palette'], theme_name)
    data
  end

  # Find theme file by name in search paths.
  def self.find_theme_file(theme_name, debug: false)
    search_paths = [
      File.join(Dir.home, '.config', 'zh', 'themes', "#{theme_name}.yaml"),
      File.join(THEMES_DIR, "#{theme_name}.yaml")
    ]

    search_paths.each do |path|
      $stderr.puts "[DEBUG] Checking theme path: #{path}" if debug
      return path if File.exist?(path)
    end

    nil
  end

  # List all available theme names.
  def self.list
    themes = []

    # Bundled themes
    Dir.glob(File.join(THEMES_DIR, '*.yaml')).each do |f|
      themes << File.basename(f, '.yaml')
    end

    # User themes
    user_themes_dir = File.join(Dir.home, '.config', 'zh', 'themes')
    if Dir.exist?(user_themes_dir)
      Dir.glob(File.join(user_themes_dir, '*.yaml')).each do |f|
        name = File.basename(f, '.yaml')
        themes << name unless themes.include?(name)
      end
    end

    themes.sort.uniq
  end

  # Validate that a palette has all required keys.
  def self.validate_palette!(palette, theme_name)
    return if palette.nil?

    missing = REQUIRED_KEYS - palette.keys
    return if missing.empty?

    raise "Theme '#{theme_name}' missing required palette keys: #{missing.join(', ')}"
  end

  # Generate gum environment variables from palette.
  def self.gum_env(palette)
    {
      'GUM_INPUT_CURSOR_FOREGROUND' => palette['accent'],
      'GUM_INPUT_PROMPT_FOREGROUND' => palette['accent_secondary'],
      'GUM_INPUT_PLACEHOLDER' => palette['fg_muted'],
      'GUM_INPUT_HEADER_FOREGROUND' => palette['accent_secondary'],
      'GUM_CHOOSE_CURSOR_FOREGROUND' => palette['accent'],
      'GUM_CHOOSE_HEADER_FOREGROUND' => palette['accent_secondary'],
      'GUM_CHOOSE_ITEM_FOREGROUND' => palette['fg'],
      'GUM_CHOOSE_SELECTED_FOREGROUND' => palette['success'],
      'GUM_CONFIRM_PROMPT_FOREGROUND' => palette['accent_secondary'],
      'GUM_CONFIRM_SELECTED_FOREGROUND' => palette['bg'],
      'GUM_CONFIRM_SELECTED_BACKGROUND' => palette['success'],
      'GUM_CONFIRM_UNSELECTED_FOREGROUND' => palette['fg_muted'],
      'GUM_FILTER_INDICATOR_FOREGROUND' => palette['accent'],
      'GUM_FILTER_SELECTED_PREFIX_FOREGROUND' => palette['success'],
      'GUM_FILTER_UNSELECTED_PREFIX_FOREGROUND' => palette['fg_muted'],
      'GUM_FILTER_HEADER_FOREGROUND' => palette['accent_secondary'],
      'GUM_FILTER_MATCH_FOREGROUND' => palette['match'],
      'GUM_FILTER_PROMPT_FOREGROUND' => palette['accent'],
      'GUM_FILTER_PLACEHOLDER' => palette['fg_muted'],
      'GUM_FILTER_CURSOR_FOREGROUND' => palette['accent'],
      'GUM_SPIN_SPINNER_FOREGROUND' => palette['accent']
    }
  end

  # Generate fzf --color option string from palette.
  def self.fzf_colors(palette)
    colors = [
      "fg:#{palette['fg']}",
      "bg:#{palette['bg']}",
      "hl:#{palette['match']}",
      "fg+:#{palette['fg']}",
      "bg+:#{palette['bg_selection']}",
      "hl+:#{palette['match']}",
      "info:#{palette['info']}",
      "prompt:#{palette['accent']}",
      "pointer:#{palette['accent']}",
      "marker:#{palette['success']}",
      "spinner:#{palette['accent_secondary']}",
      "header:#{palette['accent_secondary']}",
      "gutter:#{palette['bg']}",
      "border:#{palette['bg_highlight']}"
    ]
    colors.join(',')
  end

  # Generate FZF_DEFAULT_OPTS addition for theme colors.
  def self.fzf_opts(palette)
    "--color=#{fzf_colors(palette)}"
  end

  # Map palette to closest bat built-in theme.
  # Returns theme name string.
  def self.bat_theme(theme_data)
    # Use explicit bat_theme if defined, otherwise map by theme name
    theme_data['bat_theme'] || theme_data['name'] || 'base16'
  end

  # Generate glow glamour style JSON from palette.
  def self.glow_style(palette, theme_name)
    {
      'document' => {
        'block_prefix' => "\n",
        'block_suffix' => "\n",
        'color' => palette['fg'],
        'margin' => 2
      },
      'block_quote' => {
        'indent' => 1,
        'indent_token' => '│ ',
        'color' => palette['fg_muted']
      },
      'paragraph' => {},
      'list' => {
        'level_indent' => 2
      },
      'heading' => {
        'block_suffix' => "\n",
        'color' => palette['accent_secondary'],
        'bold' => true
      },
      'h1' => {
        'prefix' => '# ',
        'color' => palette['accent'],
        'bold' => true
      },
      'h2' => {
        'prefix' => '## ',
        'color' => palette['accent_secondary'],
        'bold' => true
      },
      'h3' => {
        'prefix' => '### ',
        'color' => palette['accent_secondary']
      },
      'h4' => {
        'prefix' => '#### ',
        'color' => palette['accent_secondary']
      },
      'h5' => {
        'prefix' => '##### ',
        'color' => palette['accent_secondary']
      },
      'h6' => {
        'prefix' => '###### ',
        'color' => palette['accent_secondary']
      },
      'text' => {},
      'strikethrough' => {
        'crossed_out' => true
      },
      'emph' => {
        'italic' => true
      },
      'strong' => {
        'bold' => true
      },
      'hr' => {
        'color' => palette['fg_muted'],
        'format' => "\n--------\n"
      },
      'item' => {
        'block_prefix' => '• '
      },
      'enumeration' => {
        'block_prefix' => '. '
      },
      'task' => {
        'ticked' => '[✓] ',
        'unticked' => '[ ] '
      },
      'link' => {
        'color' => palette['info'],
        'underline' => true
      },
      'link_text' => {
        'color' => palette['accent'],
        'bold' => true
      },
      'image' => {
        'color' => palette['info'],
        'underline' => true
      },
      'image_text' => {
        'color' => palette['accent'],
        'format' => 'Image: {{.text}}'
      },
      'code' => {
        'color' => palette['success'],
        'background_color' => palette['bg_highlight']
      },
      'code_block' => {
        'color' => palette['fg'],
        'margin' => 2,
        'chroma' => {
          'theme' => theme_name
        }
      },
      'table' => {
        'center_separator' => '┼',
        'column_separator' => '│',
        'row_separator' => '─'
      },
      'definition_list' => {},
      'definition_term' => {},
      'definition_description' => {
        'block_prefix' => "\n🠶 "
      },
      'html_block' => {},
      'html_span' => {}
    }
  end

  # Generate ripgrep color configuration.
  def self.ripgrep_colors(palette)
    [
      "match:fg:#{palette['match']}",
      "match:style:bold",
      "line:fg:#{palette['fg_muted']}",
      "path:fg:#{palette['accent_secondary']}",
      "path:style:bold"
    ]
  end

  # Export theme as shell environment variables.
  # format: :bash, :zsh, :fish
  def self.export_shell(theme_data, format: :bash)
    palette = theme_data['palette']
    theme_name = theme_data['name'] || 'custom'
    lines = []

    lines << "# ZettelHub Theme: #{theme_name}"
    lines << "# Generated by: zh theme export"
    lines << ""

    # gum
    lines << "# ─── gum ───────────────────────────────────────────────"
    gum_env(palette).each do |key, value|
      lines << export_var(key, value, format)
    end
    lines << ""

    # fzf
    lines << "# ─── fzf ───────────────────────────────────────────────"
    fzf_color_opt = fzf_opts(palette)
    case format
    when :fish
      lines << "set -gx FZF_DEFAULT_OPTS \"$FZF_DEFAULT_OPTS #{fzf_color_opt}\""
    else
      lines << "export FZF_DEFAULT_OPTS=\"$FZF_DEFAULT_OPTS #{fzf_color_opt}\""
    end
    lines << ""

    # bat
    lines << "# ─── bat ───────────────────────────────────────────────"
    lines << export_var('BAT_THEME', bat_theme(theme_data), format)
    lines << ""

    # glow
    lines << "# ─── glow ──────────────────────────────────────────────"
    glow_style_path = "~/.config/zh/themes/glow-#{theme_name}.json"
    lines << export_var('GLOW_STYLE', glow_style_path, format)
    lines << ""

    lines.join("\n")
  end

  # Format an export statement for the given shell format.
  def self.export_var(name, value, format)
    case format
    when :fish
      "set -gx #{name} \"#{value}\""
    else
      "export #{name}=\"#{value}\""
    end
  end

  # Write glow style JSON to file.
  def self.write_glow_style(theme_data, output_dir)
    palette = theme_data['palette']
    theme_name = theme_data['name'] || 'custom'
    style = glow_style(palette, theme_name)

    output_path = File.join(output_dir, "glow-#{theme_name}.json")
    File.write(output_path, JSON.pretty_generate(style))
    output_path
  end

  # Apply theme by writing config files.
  # Returns: Hash of written files
  def self.apply(theme_data, output_dir: nil)
    output_dir ||= File.join(Dir.home, '.config', 'zh', 'themes')
    FileUtils.mkdir_p(output_dir)

    written = {}

    # Write glow style
    glow_path = write_glow_style(theme_data, output_dir)
    written['glow'] = glow_path

    written
  end

  # Preview theme colors in terminal.
  def self.preview(theme_data)
    palette = theme_data['palette']
    theme_name = theme_data['name'] || 'custom'
    description = theme_data['description'] || ''

    lines = []
    lines << ""
    lines << "  Theme: #{theme_name}"
    lines << "  #{description}" unless description.empty?
    lines << ""
    lines << "  Palette:"
    lines << "  ─────────────────────────────────────"

    palette.each do |key, color|
      # Use ANSI escape codes to show color
      lines << "  #{color_swatch(color)} #{key.ljust(18)} #{color}"
    end

    lines << ""
    lines << "  Preview:"
    lines << "  ─────────────────────────────────────"
    lines << "  #{colorize('Accent text', palette['accent'])}  #{colorize('Secondary', palette['accent_secondary'])}"
    lines << "  #{colorize('Success', palette['success'])}  #{colorize('Warning', palette['warning'])}  #{colorize('Error', palette['error'])}"
    lines << "  #{colorize('Match highlight', palette['match'])}  #{colorize('Muted text', palette['fg_muted'])}"
    lines << ""

    lines.join("\n")
  end

  # Generate a color swatch using ANSI background color.
  def self.color_swatch(hex_color)
    r, g, b = hex_to_rgb(hex_color)
    "\e[48;2;#{r};#{g};#{b}m  \e[0m"
  end

  # Colorize text using ANSI foreground color.
  def self.colorize(text, hex_color)
    r, g, b = hex_to_rgb(hex_color)
    "\e[38;2;#{r};#{g};#{b}m#{text}\e[0m"
  end

  # Convert hex color to RGB values.
  def self.hex_to_rgb(hex)
    hex = hex.gsub('#', '')
    [
      hex[0..1].to_i(16),
      hex[2..3].to_i(16),
      hex[4..5].to_i(16)
    ]
  end
end
