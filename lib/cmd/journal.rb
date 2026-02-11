#!/usr/bin/env ruby
# frozen_string_literal: true

require 'date'
require 'erb'
require 'ostruct'
require_relative '../config'
require_relative '../indexer'
require_relative '../models/note'
require_relative '../utils'
require_relative '../debug'
require_relative 'add'

# Journal command: open or create a daily journal entry, then open in editor.
class JournalCommand
  include Debug

  REQUIRED_TOOLS = %w[editor].freeze

  # Handles --completion and --help; opens or creates journal for date and opens editor.
  def run(*args)
    return output_completion if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    date_spec = args.first
    date_spec = 'today' if date_spec.nil? || date_spec.strip.empty?

    resolved_date = resolve_date(date_spec.strip)
    config = Config.load(debug: debug?)

    REQUIRED_TOOLS.each do |tool_key|
      executable = Config.get_tool_command(config, tool_key)
      next if executable.to_s.strip.empty?
      msg = "Error: tool '#{tool_key}' (#{executable}) is required for zh journal. Install #{executable} and try again."
      Utils.require_command!(executable, msg)
    end

    template_config = get_template_config(config)
    template_file = Utils.find_template_file!(config['notebook_path'], template_config['template_file'], debug: debug?)
    filepath = journal_filepath_for_date(config, resolved_date, template_file)

    unless File.exist?(filepath)
      content = render_journal_template(template_file, resolved_date, config)
      add_cmd = AddCommand.new
      filepath = add_cmd.create_note_file(config, template_config, 'journal', content)
      filepath = File.expand_path(filepath)
    end

    editor_cmd = build_editor_command(config, filepath)
    system(editor_cmd)
    #Call index_note after edit to update index with new content
    index_note(config, filepath)
  end

  private

  # Prints completion candidates for shell completion.
  def output_completion
    puts 'today yesterday tomorrow'
  end

  # Prints command-specific usage and options to stdout.
  def output_help
    puts <<~HELP
      zh today       Open or create today's journal entry
      zh yesterday   Open or create yesterday's journal entry
      zh tomorrow    Open or create tomorrow's journal entry
      zh journal [DATE]  Open or create journal for DATE (default: today)
    HELP
  end

  def resolve_date(spec)
    case spec.downcase
    when 'today' then Date.today
    when 'yesterday' then Date.today - 1
    when 'tomorrow' then Date.today + 1
    else
      Date.parse(spec)
    end
  rescue ArgumentError => e
    $stderr.puts "Invalid date: #{spec} (#{e.message})"
    exit 1
  end

  def get_template_config(config)
    template_config = Config.get_template(config, 'journal', debug: debug?)
    unless template_config
      puts 'Template not found: journal'
      exit 1
    end
    template_config
  end

  # Returns the absolute path that would be used for a journal file on resolved_date,
  # using the template's config.path (ERB-rendered) or config journal path_pattern fallback.
  # Must match the path create_note_file uses so the existence check and creation refer to the same file.
  def journal_filepath_for_date(config, resolved_date, template_file)
    template_fm, = Utils.parse_front_matter(File.read(template_file))
    path_pattern = template_fm.dig('config', 'path').to_s.strip
    date_format = Config.get_engine_date_format(config)
    notebook_path = File.expand_path(config['notebook_path'])

    if path_pattern.empty?
      path_pattern = Config.get_journal_path_pattern(config)
      relative_path = Utils.interpolate_pattern(path_pattern, { 'date' => resolved_date.strftime(date_format) })
      return File.expand_path(File.join(notebook_path, relative_path))
    end

    vars = Utils.time_vars_for_date(resolved_date, date_format: date_format)
    vars['type'] = 'journal'
    vars['title'] = Utils.interpolate_pattern(Config.get_journal_default_title(config), vars)
    vars['tags'] = '[]'
    vars['description'] = ''
    vars['aliases'] = Utils.interpolate_pattern(Config.get_engine_default_alias(config), vars)
    vars['content'] ||= ''
    context = OpenStruct.new(vars)
    replacement_char = Config.get_engine_slugify_replacement(config)
    context.define_singleton_method(:slugify) { |text| Utils.slugify(text, replacement_char: replacement_char) }
    rendered_path = ERB.new(path_pattern).result(context.instance_eval { binding })
    File.expand_path(File.join(notebook_path, rendered_path.to_s.strip.sub(%r{^\./}, '')))
  end

  def render_journal_template(template_file, resolved_date, config)
    date_format = Config.get_engine_date_format(config)
    vars = Utils.time_vars_for_date(resolved_date, date_format: date_format)
    vars['type'] = 'journal'
    vars['title'] = Utils.interpolate_pattern(Config.get_journal_default_title(config), vars)
    vars['tags'] = '[]'
    vars['description'] = ''
    alias_pattern = Config.get_engine_default_alias(config)
    vars['aliases'] = Utils.interpolate_pattern(alias_pattern, vars)
    vars['content'] ||= ''
    context = OpenStruct.new(vars)
    replacement_char = Config.get_engine_slugify_replacement(config)
    context.define_singleton_method(:slugify) { |text| Utils.slugify(text, replacement_char: replacement_char) }
    template = ERB.new(File.read(template_file))
    template.result(context.instance_eval { binding })
  end

  def build_editor_command(config, filepath)
    executable = Config.get_tool_command(config, 'editor')
    opts = Config.get_tool_module_opts(config, 'editor', 'journal')
    args = Config.get_tool_module_args(config, 'editor', 'journal')
    args = args.gsub('{path}', filepath)
    Utils.build_tool_invocation(executable, opts, args)
  end

  # Indexes the note at filepath into the notebook's FTS database.
  def index_note(config, filepath)
    note = Note.new(path: filepath)
    indexer = Indexer.new(config)
    indexer.index_note(note)
  end
end

JournalCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
