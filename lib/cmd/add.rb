#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config'
require_relative '../indexer'
require_relative '../models/note'
require_relative '../utils'
require_relative '../debug'
require_relative '../git_service'
require 'erb'
require 'fileutils'
require 'ostruct'
require 'commonmarker'

# Add command for creating new notes
class AddCommand
  include Debug

  REQUIRED_TOOLS = %w[editor].freeze

  # Handles --completion and --help; creates note from template and opens editor.
  def run(*args)
    return output_completion if args.first == '--completion'
    return output_help if args.first == '--help' || args.first == '-h'

    type, title, tags, description, title_provided, tags_provided, description_provided = parse_args(args)
    debug_print("Type: #{type}")

    # Prompt for missing values only if they were not explicitly provided
    # Empty strings are treated as "explicitly provided but empty" (no prompt)
    if !title_provided && !tags_provided
      # Neither provided, prompt for both and for description
      title, tags = prompt_interactive
      description = prompt_description unless description_provided
    elsif !title_provided
      # Only tags provided, prompt for title
      title = prompt_title
      description = prompt_description unless description_provided
    elsif !tags_provided
      # Only title provided, prompt for tags
      tags = prompt_tags
      description = prompt_description unless description_provided
    end

    # Use defaults if still nil
    title ||= ''
    tags = parse_tags(tags) if tags.is_a?(String)
    tags ||= []
    description ||= ''

    config = Config.load(debug: debug?)
    REQUIRED_TOOLS.each do |tool_key|
      executable = Config.get_tool_command(config, tool_key)
      next if executable.to_s.strip.empty?
      msg = "Error: tool '#{tool_key}' (#{executable}) is required for zh add. Install #{executable} and try again."
      Utils.require_command!(executable, msg)
    end

    template_config = get_template_config(config, type)
    template_file = find_template_file(config['notebook_path'], template_config['template_file'])
    content = render_template(template_file, type, title: title, tags: tags, description: description, config: config)
    filepath = create_note_file(config, template_config, type, content)
    puts "Note created: #{filepath}"

    editor_cmd = build_editor_command(config, File.expand_path(filepath), '1')
    system(editor_cmd)
    #Call index_note after edit to update index with new content
    index_note(config, filepath)

    # Auto-commit if enabled
    auto_commit_note(config, filepath, title)
  end

  # Public API: parses front matter, applies config.path or filename_pattern, writes file, indexes, returns path.
  def create_note_file(config, template_config, type, content)
    metadata, body = Utils.parse_front_matter(content)
    default_tags = metadata.dig('config', 'default_tags') || []
    input_tags = metadata['tags'] || []
    metadata['tags'] = (Array(default_tags) + Array(input_tags)).uniq
    variables = build_variables(type, content)
    effective_pattern = metadata.dig('config', 'default_alias') || Config.get_engine_default_alias(config)
    metadata['aliases'] = Utils.interpolate_pattern(effective_pattern, variables)

    # Remove config from metadata and reconstruct content (updated aliases/tags, no config block)
    metadata_without_config = metadata.dup
    metadata_without_config.delete('config')
    content = Utils.reconstruct_note_content(metadata_without_config, body)

    # Determine filepath from template's config.path only
    path_pattern = metadata.dig('config', 'path')
    unless path_pattern
      path_pattern = '{type}-{date}.md'
    end
    filepath_relative = Utils.interpolate_pattern(path_pattern, variables)
    filepath = File.join(config['notebook_path'], filepath_relative)

    # Ensure directory exists
    FileUtils.mkdir_p(File.dirname(filepath))
    File.write(filepath, content)
    index_note(config, filepath)
    filepath
  end

  private

  def build_editor_command(config, filepath, line = '1')
    executable = Config.get_tool_command(config, 'editor')
    opts = Config.get_tool_module_opts(config, 'editor', 'add')
    args = Config.get_tool_module_args(config, 'editor', 'add')
    args = args.gsub('{path}', filepath).gsub('{line}', line)
    Utils.build_tool_invocation(executable, opts, args)
  end

  # Returns [type, title, tags, description, title_provided, tags_provided, description_provided]; type defaults to 'note'.
  def parse_args(args)
    title = nil
    tags = nil
    description = nil
    type = nil
    title_provided = false
    tags_provided = false
    description_provided = false

    i = 0
    while i < args.length
      case args[i]
      when '--title', '-t'
        title_provided = true
        # Get value if it exists
        if i + 1 < args.length
          value = args[i + 1]
          title = value unless value.to_s.strip.empty?
        end
        i += 2
      when '--tags'
        tags_provided = true
        # Get value if it exists
        if i + 1 < args.length
          value = args[i + 1]
          tags = value unless value.to_s.strip.empty?
        end
        i += 2
      when '--description', '-d'
        description_provided = true
        if i + 1 < args.length
          value = args[i + 1]
          description = value unless value.nil?
        end
        i += 2
      else
        # First non-flag argument is the type
        if type.nil? && !args[i].start_with?('--')
          type = args[i]
        end
        i += 1
      end
    end

    # Default to 'note' if no type argument was provided
    type ||= 'note'

    # Return flags indicating whether arguments were explicitly provided
    # This allows distinguishing between "not provided" (should prompt) and "provided as empty" (should not prompt)
    [type, title, tags, description, title_provided, tags_provided, description_provided]
  end

  # Splits comma-separated string into trimmed array.
  def parse_tags(tags_string)
    return [] if tags_string.nil? || tags_string.strip.empty?

    tags_string.split(',')
               .map(&:strip)
               .reject(&:empty?)
  end

  # Prompts for title and tags (e.g. via gum or stdin).
  def prompt_interactive
    title = prompt_title
    tags = prompt_tags
    [title, tags]
  end

  # Prompts for note title.
  def prompt_title
    if system('command -v gum > /dev/null 2>&1')
      `gum input --placeholder "Enter note title"`.strip
    else
      print 'Enter note title: '
      $stdin.gets.chomp
    end
  end

  # Prompts for tags (comma-separated).
  def prompt_tags
    if system('command -v gum > /dev/null 2>&1')
      input = `gum input --placeholder "Enter tags (comma-separated)"`.strip
      parse_tags(input)
    else
      print 'Enter tags (comma-separated): '
      input = $stdin.gets.chomp
      parse_tags(input)
    end
  end

  # Prompts for optional description.
  def prompt_description
    if system('command -v gum > /dev/null 2>&1')
      `gum input --placeholder "Enter note description (optional)"`.strip
    else
      print 'Enter note description (optional): '
      ($stdin.gets || '').chomp
    end
  end

  # Returns string suitable for YAML array in template (e.g. ["a","b"]).
  def format_tags_for_yaml(tags)
    return '[]' if tags.nil? || tags.empty?

    # Return inline array format that can be inserted directly into YAML
    # Escape quotes in tag values
    "[#{tags.map { |t| "\"#{t.to_s.gsub('"', '\\"')}\"" }.join(', ')}]"
  end

  # Prints completion candidates (template types) for shell completion.
  def output_completion
    begin
      config = Config.load(debug: debug?)
      types = Config.template_types(config)
      debug_print("Completion: available template types: #{types.join(', ')}")
      puts types.empty? ? Config.default_template_types.join(' ') : types.join(' ')
    rescue StandardError => e
      debug_print("Completion: error loading config: #{e.message}")
      puts Config.default_template_types.join(' ')
    end
  end

  # Prints command-specific usage and options to stdout.
  def output_help
    puts <<~HELP
      Create a new note from a template

      USAGE:
          zh add [TYPE]
          zh add [OPTIONS] [TYPE]

      DESCRIPTION:
          Creates a new note using the specified template type. TYPE defaults to 'note'
          if omitted. Available types depend on configured templates (e.g. note, journal, meeting).
          If neither --title nor --tags is provided, the command prompts interactively for title and tags.

      OPTIONS:
          --title, -t TITLE   Set the note title (can contain spaces)
          --tags TAGS         Comma-separated list of tags (e.g. "tag1, tag2")
          --description, -d  Short description or overview of the note
          --help, -h          Show this help message
          --completion        Output shell completion candidates

      EXAMPLES:
          zh add                    Create a note with default 'note' template (prompts for title/tags)
          zh add journal            Create a note with 'journal' template
          zh add --title "My Note" journal
          zh add --title "My Note" --tags "work, project"
          zh add --title "My Note" --description "Short overview"
    HELP
  end

  # Returns template config hash for type or exits with error.
  def get_template_config(config, type)
    available_types = Config.template_types(config)
    debug_print("Searching for template type: #{type}")
    debug_print("Available template types: #{available_types.join(', ')}") unless available_types.empty?

    template_config = Config.get_template(config, type, debug: debug?)
    if template_config
      debug_print("Template config found: #{template_config.inspect}")
      return template_config
    end

    debug_print("Template config not found for type: #{type}")
    puts "Template not found: #{type}"
    exit 1
  end

  # Resolves template path via Utils.find_template_file! (local then global); exits if not found.
  def find_template_file(notebook_path, template_filename)
    debug_print("Searching template file: #{template_filename}")
    template_file = Utils.find_template_file!(notebook_path, template_filename, debug: debug?)
    debug_print("Template file found: #{template_file}")
    template_file
  end

  # Renders ERB with time vars, type, title, tags, description, slugify; returns full note content.
  def render_template(template_file, type, title: '', tags: [], description: '', config: nil)
    template = ERB.new(File.read(template_file))
    date_format = config ? Config.get_engine_date_format(config) : Config.default_engine_date_format
    vars = Utils.current_time_vars(date_format: date_format)
    vars['type'] = type
    vars['title'] = title
    formatted_tags = format_tags_for_yaml(tags)
    vars['tags'] = formatted_tags
    vars['description'] = description.to_s
    # Generate alias using configured pattern
    alias_pattern = config ? Config.get_engine_default_alias(config) : Config.default_engine_default_alias
    vars['aliases'] = Utils.interpolate_pattern(alias_pattern, vars)
    # Provide default values for template variables to prevent undefined variable errors
    vars['content'] ||= ''
    # Create binding context with slugify available
    context = OpenStruct.new(vars)
    replacement_char = config ? Config.get_engine_slugify_replacement(config) : Config.default_engine_slugify_replacement
    context.define_singleton_method(:slugify) { |text| Utils.slugify(text, replacement_char: replacement_char) }
    begin
      result = template.result(context.instance_eval { binding })
      result
    rescue SyntaxError => e
      raise
    end
  end

  # Builds interpolation variables from type and parsed front matter.
  def build_variables(type, content)
    note_metadata, = Utils.parse_front_matter(content)
    Utils.current_time_vars.merge('type' => type).merge(note_metadata)
  end

  # Indexes the note at filepath into the notebook's FTS database.
  def index_note(config, filepath)
    note = Note.new(path: filepath)
    indexer = Indexer.new(config)
    indexer.index_note(note)
  end

  # Auto-commits note if git auto_commit is enabled.
  def auto_commit_note(config, filepath, title)
    return unless Config.get_git_auto_commit(config)

    notebook_path = config['notebook_path']
    git = GitService.new(notebook_path)
    return unless git.repo?

    message = "Add note: #{title.to_s.empty? ? File.basename(filepath) : title}"
    result = git.commit(message: message, paths: [filepath])

    if result[:success]
      debug_print("Auto-committed: #{message}")

      # Auto-push if enabled
      if Config.get_git_auto_push(config)
        remote = Config.get_git_remote(config)
        branch = Config.get_git_branch(config)
        push_result = git.push(remote: remote, branch: branch)
        debug_print("Auto-pushed to #{remote}/#{branch}") if push_result[:success]
      end
    else
      debug_print("Auto-commit failed: #{result[:message]}")
    end
  end
end

AddCommand.new.run(*ARGV) if __FILE__ == $PROGRAM_NAME
