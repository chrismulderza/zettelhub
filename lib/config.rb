# frozen_string_literal: true

require 'rbconfig'
require 'yaml'

# Configuration handling for ZettelHub. Resolves notebook path, loads YAML, and provides path/template/tool accessors.
class Config
  CONFIG_DIR = File.join(ENV['HOME'], '.config', 'zh')
  CONFIG_FILE = File.join(CONFIG_DIR, 'config.yaml')
  ZH_DIRNAME = '.zh'

  # Bundled templates (lib/templates); used when no user templates exist.
  def self.bundled_templates_dir
    File.join(File.dirname(__FILE__), 'templates')
  end

  # Path helpers: single source for .zh, index, config, templates
  def self.zh_dir(notebook_path)
    File.join(notebook_path, ZH_DIRNAME)
  end

  # Path to local config file (.zh/config.yaml).
  def self.local_config_path(notebook_path)
    File.join(zh_dir(notebook_path), 'config.yaml')
  end

  # Path to index SQLite DB (.zh/index.db).
  def self.index_db_path(notebook_path)
    File.join(zh_dir(notebook_path), 'index.db')
  end

  # Path to local templates dir (.zh/templates).
  def self.local_templates_dir(notebook_path)
    File.join(zh_dir(notebook_path), 'templates')
  end

  # Config base dir at call time (respects ENV['HOME'] for tests)
  def self.config_dir_at_runtime
    File.join(ENV['HOME'] || Dir.home, '.config', 'zh')
  end

  # Path to global templates dir (~/.config/zh/templates).
  def self.global_templates_dir
    File.join(config_dir_at_runtime, 'templates')
  end

  # Find .zh directory by walking up from start_path until reaching home
  def self.find_zh_directory(start_path, debug: false)
    debug_print = ->(msg) { $stderr.puts("[DEBUG] #{msg}") if debug }
    
    current = File.expand_path(start_path)
    home = File.expand_path(ENV['HOME'] || Dir.home)
    
    loop do
      zh_dir = File.join(current, ZH_DIRNAME)
      if File.directory?(zh_dir)
        debug_print.call("Found .zh directory at: #{zh_dir}")
        return zh_dir
      end
      
      # Stop if we've reached home directory
      break if current == home || current == File.dirname(current)
      
      current = File.dirname(current)
    end
    
    nil
  end

  # Resolve notebook path and config using hierarchical resolution
  def self.resolve_notebook_path(debug: false) # rubocop:disable Metrics/MethodLength
    debug_print = ->(msg) { $stderr.puts("[DEBUG] #{msg}") if debug }
    searched_locations = []
    
    # 1. Check current working directory
    debug_print.call("Step 1: Checking current working directory for .zh")
    cwd = Dir.pwd
    zh_dir = find_zh_directory(cwd, debug: debug)
    if zh_dir
      notebook_path = File.dirname(zh_dir)
      config_file = local_config_path(notebook_path)
      if File.exist?(config_file)
        debug_print.call("Found config via CWD: #{config_file}")
        return { config_file: config_file, notebook_path: notebook_path, source: 'cwd' }
      end
    end
    searched_locations << "CWD and parent directories up to home"
    
    # 2. Walk up directory tree (already done in find_zh_directory, but check explicitly)
    # This is handled by find_zh_directory which walks up automatically

    # 3. Check ZH_NOTEBOOK_PATH environment variable
    if ENV['ZH_NOTEBOOK_PATH']
      debug_print.call("Step 3: Checking ZH_NOTEBOOK_PATH environment variable")
      env_path = File.expand_path(ENV['ZH_NOTEBOOK_PATH'])
      zh_dir = zh_dir(env_path)
      if File.directory?(zh_dir)
        config_file = local_config_path(env_path)
        if File.exist?(config_file)
          debug_print.call("Found config via ZH_NOTEBOOK_PATH: #{config_file}")
          return { config_file: config_file, notebook_path: env_path, source: 'env' }
        end
      end
      searched_locations << "ZH_NOTEBOOK_PATH: #{env_path}"
    end
    
    # 4. Fall back to global config
    debug_print.call("Step 4: Checking global config location")
    if File.exist?(CONFIG_FILE)
      debug_print.call("Found global config: #{CONFIG_FILE}")
      global_config = load_config(CONFIG_FILE)
      if global_config && global_config['notebook_path']
        notebook_path = File.expand_path(global_config['notebook_path'])
        return { config_file: CONFIG_FILE, notebook_path: notebook_path, source: 'global' }
      end
    end
    searched_locations << "Global config: #{CONFIG_FILE}"
    
    # No config found
    error_msg = "No config file found. Searched locations:\n"
    searched_locations.each { |loc| error_msg += "  - #{loc}\n" }
    raise error_msg
  end

  # Loads and returns config hash from resolved file (hierarchical resolution, merge local/global).
  def self.load(debug: false) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    debug_print = ->(msg) { $stderr.puts("[DEBUG] #{msg}") if debug }
    
    # Resolve notebook path using hierarchical resolution
    resolution = resolve_notebook_path(debug: debug)
    config_file = resolution[:config_file]
    notebook_path = File.expand_path(resolution[:notebook_path])
    source = resolution[:source]
    
    debug_print.call("Config resolution: found via #{source}")
    debug_print.call("Config file: #{config_file}")
    debug_print.call("Notebook path: #{notebook_path}")
    
    # Load the primary config
    primary_config = load_config(config_file)
    raise "Config file found but could not be loaded: #{config_file}" unless primary_config
    
    # If config was found via directory walk or env var, set notebook_path to parent of .zh
    # Otherwise, use notebook_path from config file (for global config)
    if source == 'cwd' || source == 'env'
      primary_config['notebook_path'] = notebook_path
      debug_print.call("Set notebook_path to resolved path: #{notebook_path}")
    elsif source == 'global'
      # Use notebook_path from global config, but expand it
      if primary_config['notebook_path']
        primary_config['notebook_path'] = File.expand_path(primary_config['notebook_path'])
        notebook_path = primary_config['notebook_path']
        debug_print.call("Using notebook_path from global config: #{notebook_path}")
      end
    end
    
    # Try to merge with global config if we found a local config
    merged_config = primary_config.dup
    if source == 'cwd' || source == 'env'
      # Check for global config to merge with
      if File.exist?(CONFIG_FILE) && config_file != CONFIG_FILE
        debug_print.call("Merging with global config: #{CONFIG_FILE}")
        global_config = load_config(CONFIG_FILE)
        merged_config = global_config.merge(primary_config) if global_config
        debug_print.call("Merged: local config overrides global") if global_config
      end
    elsif source == 'global'
      # Check for local config at the notebook_path
      local_config_file = local_config_path(notebook_path)
      debug_print.call("Checking for local config at notebook_path: #{local_config_file}")
      local_config = load_config(local_config_file)
      if local_config
        debug_print.call("Local config found, merging with global")
        merged_config = primary_config.merge(local_config)
      else
        debug_print.call("No local config found, using global only")
      end
    end

    # Ensure notebook_path is set and expanded
    merged_config['notebook_path'] = File.expand_path(notebook_path)

    if debug
      types = discover_templates(merged_config['notebook_path']).map { |t| t['type'] }.uniq.sort
      debug_print.call("Discovered template types: #{types.join(', ')}")
    end

    merged_config
  end

  # Load config and validate notebook path exists; exit with error message if not.
  # Returns the config hash. Use in commands that require a valid notebook directory.
  def self.load_with_notebook(debug: false)
    config = load(debug: debug)
    notebook_path = config['notebook_path']
    unless notebook_path && Dir.exist?(notebook_path)
      $stderr.puts "Error: Notebook path not found: #{notebook_path}"
      exit 1
    end
    config
  end

  # Reads and parses YAML from file path; returns nil if file missing.
  def self.load_config(file)
    YAML.load_file(file) if File.exist?(file)
  end

  # Discover templates by enumerating .erb files from bundled, global, and local dirs.
  # Merge by basename: local overrides global overrides bundled. Infer type from each template's front matter.
  # Returns array of hashes with 'type' and 'template_file' (basename only).
  def self.discover_templates(notebook_path)
    dirs = [bundled_templates_dir, global_templates_dir, local_templates_dir(notebook_path)]
    by_basename = {}
    dirs.each do |dir|
      next unless File.directory?(dir)
      Dir.glob(File.join(dir, '*.erb')).each do |path|
        by_basename[File.basename(path)] = path
      end
    end
    by_basename.map do |template_file, full_path|
      type = infer_template_type(full_path, template_file)
      { 'type' => type, 'template_file' => template_file }
    end
  end

  # Extract YAML front matter (first --- to second ---) and read type. If type value contains ERB, use filename stem.
  def self.infer_template_type(template_path, template_file)
    return File.basename(template_file, '.erb') unless File.exist?(template_path)
    content = File.read(template_path)
    return File.basename(template_file, '.erb') unless content.start_with?('---')
    parts = content.split('---', 3)
    return File.basename(template_file, '.erb') if parts.size < 2
    front = parts[1]
    # Look for type: value (literal or quoted)
    if front =~ /^\s*type:\s*["']?([^"'\s<]+)["']?\s*$/m
      return Regexp.last_match(1).strip
    end
    if front =~ /^\s*type:\s*<%=/
      return File.basename(template_file, '.erb')
    end
    if front =~ /^\s*type:\s*(.+)$/m
      v = Regexp.last_match(1).strip
      return v unless v.include?('<%')
      return File.basename(template_file, '.erb')
    end
    File.basename(template_file, '.erb')
  end

  # Return config.dig(*path) or nil; safe when config is nil.
  def self.dig_config(config, *path)
    return nil if path.empty?
    config&.dig(*path.map(&:to_s))
  end

  # Returns template config hash for name (type), or nil if not found. Uses discovery only.
  def self.get_template(config, name, debug: false)
    return nil if config.nil?
    notebook_path = config['notebook_path']
    return nil unless notebook_path
    debug_print = ->(msg) { $stderr.puts("[DEBUG] #{msg}") if debug }
    templates = discover_templates(notebook_path)
    template = templates.find { |t| t['type'] == name }
    if template
      debug_print.call("Found template with type '#{name}'")
      normalize_template(template)
    else
      debug_print.call("No template found with type '#{name}'")
      nil
    end
  end

  # Ensures template has type and template_file (discovery returns only those; no filename_pattern/subdirectory).
  def self.normalize_template(template)
    {
      'type' => template['type'],
      'template_file' => template['template_file'] || "#{template['type']}.erb"
    }
  end

  # Default template types used when config cannot be loaded (e.g. completion fallback).
  def self.default_template_types
    %w[note journal meeting bookmark]
  end

  # Returns sorted, unique list of template types from discovery, or [] if no notebook_path.
  def self.template_types(config)
    return [] if config.nil?
    notebook_path = config['notebook_path']
    return [] unless notebook_path
    discover_templates(notebook_path).map { |t| t['type'] }.compact.uniq.sort
  end

  # Default date format for templates (strftime; ISO 8601).
  def self.default_engine_date_format
    '%Y-%m-%d' # ISO 8601 format
  end

  # Returns date format from config or default.
  def self.get_engine_date_format(config)
    dig_config(config, 'engine', 'date_format') || default_engine_date_format
  end

  # Default replacement character for slugify (e.g. hyphen).
  def self.default_engine_slugify_replacement
    '-' # Hyphen as default replacement
  end

  # Returns slugify replacement from config or default.
  def self.get_engine_slugify_replacement(config)
    dig_config(config, 'engine', 'slugify_replacement') || default_engine_slugify_replacement
  end

  # Default journal path pattern (relative to notebook).
  def self.default_journal_path_pattern
    'journal/{date}.md'
  end

  # Returns journal path pattern from config or default.
  def self.get_journal_path_pattern(config)
    dig_config(config, 'journal', 'path_pattern') || default_journal_path_pattern
  end

  # Default journal title template.
  def self.default_journal_default_title
    'Journal for {date}'
  end

  # Returns journal default title from config or default.
  def self.get_journal_default_title(config)
    dig_config(config, 'journal', 'default_title') || default_journal_default_title
  end

  # Default alias pattern for notes (e.g. "{type}> {date}: {title}").
  def self.default_engine_default_alias
    '{type}> {date}: {title}' # Format: "note> 2024-01-15: Title"
  end

  # Returns default alias pattern from config or default.
  def self.get_engine_default_alias(config)
    dig_config(config, 'engine', 'default_alias') || default_engine_default_alias
  end

  # Default delimiter for DB result display (e.g. pipe).
  def self.default_engine_db_result_delimiter
    '|'
  end

  # Returns DB result delimiter from config or default.
  def self.get_engine_db_result_delimiter(config)
    v = dig_config(config, 'engine', 'db_result_delimiter')
    (v.nil? || v.to_s.strip.empty?) ? default_engine_db_result_delimiter : v.to_s.strip
  end

  # Tool executable only (tools.<key>.command). Used for validation and as first segment of invocation.
  # For 'editor': prefer ENV['EDITOR'] if set, then config, then 'editor'.
  def self.get_tool_command(config, tool_key)
    if tool_key.to_s == 'editor'
      editor = ENV['EDITOR'].to_s.strip
      return editor unless editor.empty?
    end
    cmd = dig_config(config, 'tools', tool_key.to_s, 'command')
    return cmd.to_s.strip if cmd && !cmd.to_s.strip.empty?
    case tool_key.to_s
    when 'matcher' then 'rg'
    when 'filter' then 'fzf'
    when 'editor' then 'editor'
    when 'reader' then 'glow'
    when 'preview' then 'bat'
    when 'open'
      host_os = RbConfig::CONFIG['host_os'] || ''
      (host_os =~ /darwin|mac os/i) ? 'open' : 'xdg-open'
    else ''
    end
  end

  # Args string for tool in module (tools.<key>.<module>.args). Placeholders e.g. {1}, {2}, {-1}.
  def self.get_tool_module_args(config, tool_key, module_name)
    v = dig_config(config, 'tools', tool_key.to_s, module_name.to_s, 'args')
    return v.to_s.strip if v && !v.to_s.strip.empty?
    default_tool_module_args(tool_key.to_s, module_name.to_s)
  end

  # Default args string for tool+module (placeholders {1}, {2}, etc.).
  def self.default_tool_module_args(tool_key, module_name)
    case [tool_key, module_name]
    when ['editor', 'find'] then '{1} +{2}'
    when ['editor', 'search'] then '{-1}'
    when ['editor', 'add'] then '{path} +{line}'
    when ['editor', 'journal'] then '{path}'
    when ['preview', 'find'] then '{1} --highlight-line {2}'
    when ['preview', 'search'] then '{-1} --highlight-line 1'
    when ['open', 'find'] then '{1}'
    when ['open', 'search'] then '{-1}'
    when ['reader', 'find'] then '{1}'
    when ['reader', 'search'] then '{-1}'
    else ''
    end
  end

  # Opts array for tool in module (tools.<key>.<module>.opts). Static CLI options.
  def self.get_tool_module_opts(config, tool_key, module_name)
    v = dig_config(config, 'tools', tool_key.to_s, module_name.to_s, 'opts')
    return v.map(&:to_s).reject { |s| s.strip.empty? } if v.is_a?(Array)
    default_tool_module_opts(tool_key.to_s, module_name.to_s)
  end

  # Default opts array for tool+module (static CLI options).
  def self.default_tool_module_opts(tool_key, module_name)
    case [tool_key, module_name]
    when ['filter', 'find'] then ['--ansi', '--disabled']
    when ['filter', 'bookmark'] then []
    when ['preview', 'find'], ['preview', 'search'] then ['--color=always']
    when ['matcher', 'find'] then ['--line-number', '--no-heading', '--color=always', '--smart-case']
    else []
    end
  end

  # Default filter keybindings (enter, ctrl-r, ctrl-o).
  def self.default_tools_filter_keybindings
    [
      'enter:execute({editor_command})',
      'ctrl-r:execute({reader_command})',
      'ctrl-o:execute({open_command})'
    ]
  end

  # Returns filter keybindings from config or default.
  def self.get_tools_filter_keybindings(config)
    v = dig_config(config, 'tools', 'filter', 'keybindings')
    return default_tools_filter_keybindings if v.nil? || !v.is_a?(Array)
    v.map(&:to_s).reject { |s| s.strip.empty? }
  end

  # Substitute {editor_command}, {reader_command}, {open_command} in keybinding strings.
  def self.substitute_filter_keybinding_placeholders(str, editor_command:, reader_command:, open_command:)
    s = str.to_s
    s = s.gsub('{editor_command}', editor_command.to_s)
    s = s.gsub('{reader_command}', reader_command.to_s)
    s = s.gsub('{open_command}', open_command.to_s)
    s
  end

  # Fzf display format for search (7 fields: rank, id, type, date, title, tags, path).
  def self.default_tools_filter_search_display_format
    '{1}>{3}>{4},{5} (id:{2}) [tags:{6}]'
  end

  # Returns search display format from config or default.
  def self.get_tools_filter_search_display_format(config)
    format = dig_config(config, 'tools', 'filter', 'search', 'display_format')
    (format.nil? || format.to_s.strip.empty?) ? default_tools_filter_search_display_format : format.to_s.strip
  end

  # Default fzf select expression for search (e.g. -1 for last field).
  def self.default_tools_filter_select_expression
    '-1'
  end

  # Returns search select expression from config or default.
  def self.get_tools_filter_search_select_expression(config)
    v = dig_config(config, 'tools', 'filter', 'search', 'select_expression')
    (v.nil? || v.to_s.strip.empty?) ? default_tools_filter_select_expression : v.to_s.strip
  end

  # Search command: default result limit.
  def self.default_search_limit
    100
  end

  # Returns search limit from config or default.
  def self.get_search_limit(config)
    v = dig_config(config, 'search', 'limit')
    (v.nil? || !v.is_a?(Integer) || v < 1) ? default_search_limit : v
  end

  # Find command: ripgrep glob for file matching. Returns array of patterns (e.g. ['*.md', '*.txt']).
  def self.default_find_glob
    ['*.md', '*.txt', '*.markdown']
  end

  # Returns find glob from config or default.
  def self.get_find_glob(config)
    v = dig_config(config, 'find', 'glob')
    return default_find_glob if v.nil?
    arr = v.is_a?(Array) ? v : [v.to_s]
    arr = arr.map(&:to_s).reject { |s| s.strip.empty? }
    arr.empty? ? default_find_glob : arr
  end

  # Find command: ripgrep glob to ignore. Returns array of patterns (e.g. ['!.zh']).
  def self.default_find_ignore_glob
    ['!.zh', '!.git', '!.DS_Store']
  end

  # Returns find ignore glob from config or default.
  def self.get_find_ignore_glob(config)
    v = dig_config(config, 'find', 'ignore_glob')
    return default_find_ignore_glob if v.nil?
    arr = v.is_a?(Array) ? v : [v.to_s]
    arr = arr.map(&:to_s).reject { |s| s.strip.empty? }
    arr.empty? ? default_find_ignore_glob : arr
  end

  # Find command: delay in seconds before reload on change (e.g. 0.1).
  def self.default_find_reload_delay
    0.1
  end

  # Returns find reload delay from config or default.
  def self.get_find_reload_delay(config)
    v = dig_config(config, 'find', 'reload_delay')
    if v.nil?
      default_find_reload_delay
    else
      f = Float(v) rescue default_find_reload_delay
      f.positive? ? f : default_find_reload_delay
    end
  end

  # Import command: default target directory (relative to notebook_path) when --into not given.
  def self.default_import_target_dir
    '.'
  end

  # Returns import default target dir from config or default.
  def self.get_import_default_target_dir(config)
    v = dig_config(config, 'import', 'default_target_dir')
    v.nil? || v.to_s.strip.empty? ? default_import_target_dir : v.to_s.strip
  end

  # Default fzf preview window (e.g. up:60%).
  def self.default_tools_filter_preview_window
    'up:60%'
  end

  # Returns search preview window from config or default.
  def self.get_tools_filter_search_preview_window(config)
    v = dig_config(config, 'tools', 'filter', 'search', 'preview_window')
    v = dig_config(config, 'tools', 'filter', 'preview_window') if v.nil? || (v.respond_to?(:to_s) && v.to_s.strip.empty?)
    v.nil? || (v.respond_to?(:to_s) && v.to_s.strip.empty?) ? default_tools_filter_preview_window : v.to_s
  end

  # Returns find preview window from config or default.
  def self.get_tools_filter_find_preview_window(config)
    v = dig_config(config, 'tools', 'filter', 'find', 'preview_window')
    v = dig_config(config, 'tools', 'filter', 'preview_window') if v.nil? || (v.respond_to?(:to_s) && v.to_s.strip.empty?)
    v.nil? || (v.respond_to?(:to_s) && v.to_s.strip.empty?) ? default_tools_filter_preview_window : v.to_s
  end

  # Default search filter header (key hints).
  def self.default_tools_filter_search_header
    'Search: Enter=edit | Ctrl-r=read | Ctrl-o=open'
  end

  # Returns search header from config or default.
  def self.get_tools_filter_search_header(config)
    v = dig_config(config, 'tools', 'filter', 'search', 'header')
    v = dig_config(config, 'tools', 'filter', 'header') if v.nil? || (v.respond_to?(:to_s) && v.to_s.strip.empty?)
    v.nil? || (v.respond_to?(:to_s) && v.to_s.strip.empty?) ? default_tools_filter_search_header : v.to_s
  end

  # Generic filter header (tools.filter.header). For search use get_tools_filter_search_header; for find use get_tools_filter_find_header.
  def self.get_tools_filter_header(config)
    v = dig_config(config, 'tools', 'filter', 'header')
    v.nil? || (v.respond_to?(:to_s) && v.to_s.strip.empty?) ? default_tools_filter_search_header : v.to_s
  end

  # Find command: header line (e.g. key hints).
  def self.default_tools_filter_find_header
    'Find: Enter=edit | Ctrl-r=read | Ctrl-o=open'
  end

  # Returns find header: tools.filter.find.header then tools.filter.search.header then default.
  def self.get_tools_filter_find_header(config)
    v = dig_config(config, 'tools', 'filter', 'find', 'header')
    v = dig_config(config, 'tools', 'filter', 'search', 'header') if v.nil? || v.to_s.strip.empty?
    v = default_tools_filter_find_header if v.nil? || v.to_s.strip.empty?
    v.to_s
  end

  # --- Git Configuration ---

  # Default git auto-commit setting (false).
  def self.default_git_auto_commit
    false
  end

  # Returns git auto-commit setting from config or default.
  def self.get_git_auto_commit(config)
    v = dig_config(config, 'git', 'auto_commit')
    v.nil? ? default_git_auto_commit : !!v
  end

  # Default git auto-push setting (false).
  def self.default_git_auto_push
    false
  end

  # Returns git auto-push setting from config or default.
  def self.get_git_auto_push(config)
    v = dig_config(config, 'git', 'auto_push')
    v.nil? ? default_git_auto_push : !!v
  end

  # Default git remote name.
  def self.default_git_remote
    'origin'
  end

  # Returns git remote name from config or default.
  def self.get_git_remote(config)
    v = dig_config(config, 'git', 'remote')
    v.nil? || v.to_s.strip.empty? ? default_git_remote : v.to_s.strip
  end

  # Default git branch name.
  def self.default_git_branch
    'main'
  end

  # Returns git branch name from config or default.
  def self.get_git_branch(config)
    v = dig_config(config, 'git', 'branch')
    v.nil? || v.to_s.strip.empty? ? default_git_branch : v.to_s.strip
  end

  # Default commit message template.
  def self.default_git_commit_message_template
    'Update notes: {changed_count} file(s)'
  end

  # Returns commit message template from config or default.
  def self.get_git_commit_message_template(config)
    v = dig_config(config, 'git', 'commit_message_template')
    v.nil? || v.to_s.strip.empty? ? default_git_commit_message_template : v.to_s
  end

  # Default history limit for git log.
  def self.default_git_history_limit
    20
  end

  # Returns history limit from config or default.
  def self.get_git_history_limit(config)
    v = dig_config(config, 'git', 'history_limit')
    (v.nil? || !v.is_a?(Integer) || v < 1) ? default_git_history_limit : v
  end

end
