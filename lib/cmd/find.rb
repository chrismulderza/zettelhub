#!/usr/bin/env ruby
# frozen_string_literal: true

require 'shellwords'
require_relative '../config'
require_relative '../utils'
require_relative '../debug'

# Interactive find command: ripgrep over notebook markdown, fzf UI
class FindCommand
  include Debug

  # Tools subkeys from config required by find; executable is validated for availability.
  REQUIRED_TOOLS = %w[matcher filter].freeze

  # Handles --completion and --help; runs rg + fzf and opens selected note in editor/reader/open.
  def run(*args)
    return output_completion if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    initial_query = parse_args(args) || ''
    debug_print("Initial query: #{initial_query}")

    config = Config.load_with_notebook(debug: debug?)
    notebook_path = config['notebook_path']

    REQUIRED_TOOLS.each do |tool_key|
      executable = Config.get_tool_command(config, tool_key)
      next if executable.to_s.strip.empty?
      msg = "Error: tool '#{tool_key}' (#{executable}) is required for zh find. Install #{executable} and try again."
      Utils.require_command!(executable, msg)
    end

    run_filter(config, notebook_path, initial_query)
  end

  private

  # Returns first non-option argument (initial query) or nil.
  def parse_args(args)
    i = 0
    while i < args.length
      return nil if args[i] == '--help' || args[i] == '-h' || args[i] == '--completion'
      return args[i] if !args[i].start_with?('--')

      i += 1
    end
    nil
  end

  # Builds rg + fzf command with reload bindings, preview, keybindings; runs fzf via IO.popen and blocks until exit.
  def run_filter(config, notebook_path, initial_query)
    filter_executable = Config.get_tool_command(config, 'filter')
    filter_opts = Config.get_tool_module_opts(config, 'filter', 'find')
    path_escaped = Shellwords.shellescape(File.expand_path(notebook_path))
    glob_opts = Config.get_find_glob(config).map { |g| "--glob #{Shellwords.shellescape(g)}" }.join(' ')
    ignore_opts = Config.get_find_ignore_glob(config).map { |g| "--glob #{Shellwords.shellescape(g)}" }.join(' ')
    matcher_executable = Config.get_tool_command(config, 'matcher')
    matcher_opts = Config.get_tool_module_opts(config, 'matcher', 'find')
    rg_prefix = "#{matcher_executable} #{matcher_opts.join(' ')} #{glob_opts} #{ignore_opts} "
    reload_delay = Config.get_find_reload_delay(config)
    previewer_available = Utils.command_available?(Config.get_tool_command(config, 'preview'))

    preview_exec = previewer_available ? Config.get_tool_command(config, 'preview') : 'cat'
    preview_opts = previewer_available ? Config.get_tool_module_opts(config, 'preview', 'find') : []
    preview_args = previewer_available ? Config.get_tool_module_args(config, 'preview', 'find') : '{1}'
    preview_cmd = Utils.build_tool_invocation(preview_exec, preview_opts, preview_args)

    preview_window = Config.get_tools_filter_find_preview_window(config)
    header = Config.get_tools_filter_find_header(config)
    editor_cmd = Utils.build_tool_invocation(
      Config.get_tool_command(config, 'editor'),
      Config.get_tool_module_opts(config, 'editor', 'find'),
      Config.get_tool_module_args(config, 'editor', 'find')
    )
    open_cmd = Utils.build_tool_invocation(
      Config.get_tool_command(config, 'open'),
      Config.get_tool_module_opts(config, 'open', 'find'),
      Config.get_tool_module_args(config, 'open', 'find')
    )
    reader_available = Utils.command_available?(Config.get_tool_command(config, 'reader'))
    reader_exec = reader_available ? Config.get_tool_command(config, 'reader') : 'less'
    reader_cmd = Utils.build_tool_invocation(
      reader_exec,
      Config.get_tool_module_opts(config, 'reader', 'find'),
      Config.get_tool_module_args(config, 'reader', 'find')
    )

    # Keybindings: config (placeholders substituted)
    raw_bindings = Config.get_tools_filter_keybindings(config)
    bind_parts = raw_bindings.map do |s|
      Config.substitute_filter_keybinding_placeholders(
        s,
        editor_command: editor_cmd,
        reader_command: reader_cmd,
        open_command: open_cmd
      )
    end

    filter_cmd = [
      filter_executable,
      *filter_opts,
      '--query', initial_query.to_s,
      '--prompt', 'Pattern> ',
      '--bind', "start:reload:#{rg_prefix} {q} #{path_escaped}",
      '--bind', "change:reload:sleep #{reload_delay}; #{rg_prefix} {q} #{path_escaped} || true",
      '--delimiter', ':',
      '--preview', preview_cmd,
      '--preview-window', preview_window,
      '--header', header,
      '--bind', bind_parts.join(',')
    ]

    debug_print("Filter command: #{filter_cmd.inspect}")

    IO.popen(ENV.to_h, filter_cmd, 'r') do |io|
      # Filter uses reload so no stdin; block until filter exits (e.g. Enter -> become(editor))
      io.read
    end
  rescue StandardError => e
    $stderr.puts "Error in find: #{e.message}"
    exit 1
  end

  # Prints completion candidates for shell completion (empty for find).
  def output_completion
    puts ''
  end

  # Prints command-specific usage and options to stdout.
  def output_help
    puts <<~HELP
      Interactive find in note content (ripgrep + fzf)

      USAGE:
          zh find [query]

      DESCRIPTION:
          Searches note content under the notebook directory using ripgrep;
          fzf shows results as you type. Enter opens the selected file at
          line in your editor.

      OPTIONS:
          --help, -h       Show this help message
          --completion     Output shell completion candidates

      KEY BINDINGS (default, from config):
          Enter     Open selected file at line in editor
          Ctrl-r    Read selected file (reader)
          Ctrl-o    Open selected file (system)

      CONFIG (optional in config.yaml):
          editor_command   Editor template; placeholders {path}, {line} (find: {1}=path, {2}=line)
          preview_command  Preview template; placeholders {path}, {line}
          open_command     Open (system); placeholder {path}
          filter_find_header  Header line (key hints)

      EXAMPLES:
          zh find              Start find with empty query
          zh find "meeting"    Start find with initial query "meeting"
    HELP
  end
end

FindCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
