# frozen_string_literal: true

require 'shellwords'
require_relative 'option_source'
require_relative 'value_transformer'
require_relative 'value_validator'

# Executes individual prompts by type.
# Supports: input, write, choose, filter, confirm.
# Choose and filter support multi: true for multiple selection.
module PromptExecutor
  # Executes a prompt and returns the collected value.
  # prompt_def is the prompt definition hash from template config.
  # config is the ZettelHub config.
  # vars is the current variable context.
  def self.execute(prompt_def, config, vars = {})
    type = prompt_def['type']&.to_s&.downcase || 'input'
    placeholder = prompt_def['prompt'] || prompt_def['placeholder'] || prompt_def['label'] || "Enter #{prompt_def['key']}"
    default_value = resolve_default(prompt_def['default'], vars)
    options = resolve_options(prompt_def, config, vars)
    multi = prompt_def['multi'] == true

    value = case type
            when 'input'
              prompt_input(placeholder, default_value)
            when 'write'
              prompt_write(placeholder, default_value)
            when 'choose'
              multi ? prompt_choose_multi(placeholder, options) : prompt_choose(placeholder, options, default_value)
            when 'filter'
              multi ? prompt_filter_multi(placeholder, options) : prompt_filter(placeholder, options, default_value, prompt_def['allow_new'])
            when 'confirm'
              prompt_confirm(placeholder, default_value)
            else
              prompt_input(placeholder, default_value)
            end

    # Apply transformations
    value = ValueTransformer.apply(value, prompt_def['transform']) if prompt_def['transform']

    value
  end

  # Resolves default value (may contain ERB).
  def self.resolve_default(default, vars)
    return nil if default.nil?
    return default unless default.is_a?(String) && default.include?('<%')

    require_relative 'template_vars'
    TemplateVars.render_erb_value(default, vars)
  rescue StandardError
    default
  end

  # Resolves options from static list or dynamic source.
  def self.resolve_options(prompt_def, config, vars)
    if prompt_def['options']
      Array(prompt_def['options'])
    elsif prompt_def['source']
      options = OptionSource.resolve(prompt_def['source'], config, vars)
      OptionSource.to_display_values(options)
    else
      []
    end
  end

  # Prompts for single-line text input.
  def self.prompt_input(placeholder, default = nil)
    if gum_available?
      cmd = ['gum', 'input', '--header', placeholder, '--placeholder', 'Type here...']
      cmd += ['--value', default] if default
      result = `#{cmd.shelljoin}`
      # Check if gum succeeded; fall back to stdin if it failed
      if $?.success?
        result.strip
      else
        warn "[gum failed, falling back to stdin]"
        fallback_input(placeholder, default)
      end
    else
      fallback_input(placeholder, default)
    end
  end

  # Stdin fallback for input prompt.
  def self.fallback_input(placeholder, default)
    print_prompt(placeholder, default)
    input = $stdin.gets&.chomp || ''
    input.empty? && default ? default : input
  end

  # Prompts for multi-line text input.
  def self.prompt_write(placeholder, default = nil)
    if gum_available?
      cmd = ['gum', 'write', '--header', placeholder, '--placeholder', 'Type here...']
      cmd += ['--value', default] if default
      result = `#{cmd.shelljoin}`
      if $?.success?
        result.strip
      else
        warn "[gum failed, falling back to stdin]"
        fallback_write(placeholder, default)
      end
    else
      fallback_write(placeholder, default)
    end
  end

  # Stdin fallback for multi-line input.
  def self.fallback_write(placeholder, default)
    puts "#{placeholder} (enter empty line to finish):"
    lines = []
    loop do
      line = $stdin.gets
      break if line.nil? || line.strip.empty?

      lines << line.chomp
    end
    result = lines.join("\n")
    result.empty? && default ? default : result
  end

  # Prompts to choose from options.
  def self.prompt_choose(placeholder, options, default = nil)
    return default if options.empty?

    if gum_available?
      cmd = ['gum', 'choose', '--header', placeholder] + options
      result = `#{cmd.shelljoin}`
      if $?.success?
        result = result.strip
        result.empty? ? default : result
      else
        warn "[gum failed, falling back to stdin]"
        fallback_choose(placeholder, options, default)
      end
    else
      fallback_choose(placeholder, options, default)
    end
  end

  # Stdin fallback for choose prompt.
  def self.fallback_choose(placeholder, options, default)
    puts "#{placeholder}:"
    options.each_with_index { |opt, i| puts "  #{i + 1}. #{opt}" }
    print 'Enter number: '
    input = $stdin.gets&.chomp || ''
    idx = input.to_i - 1
    (0...options.size).cover?(idx) ? options[idx] : (default || options.first)
  end

  # Prompts to choose multiple items from options. Returns array.
  def self.prompt_choose_multi(placeholder, options)
    return [] if options.empty?

    if gum_available?
      cmd = ['gum', 'choose', '--no-limit', '--header', "#{placeholder} (space to select, enter to confirm)"] + options
      result = `#{cmd.shelljoin}`
      if $?.success?
        result.strip.split("\n").map(&:strip).reject(&:empty?)
      else
        warn "[gum failed, falling back to stdin]"
        fallback_choose_multi(placeholder, options)
      end
    else
      fallback_choose_multi(placeholder, options)
    end
  end

  # Stdin fallback for multi-select choose.
  def self.fallback_choose_multi(placeholder, options)
    puts "#{placeholder} (enter comma-separated numbers, e.g., 1,3,5):"
    options.each_with_index { |opt, i| puts "  #{i + 1}. #{opt}" }
    print 'Enter numbers: '
    input = $stdin.gets&.chomp || ''
    return [] if input.strip.empty?

    indices = input.split(',').map { |s| s.strip.to_i - 1 }
    indices.select { |i| (0...options.size).cover?(i) }.map { |i| options[i] }
  end

  # Prompts with fuzzy filter from options.
  def self.prompt_filter(placeholder, options, default = nil, allow_new = false)
    return prompt_input(placeholder, default) if options.empty?

    if gum_available?
      cmd = ['gum', 'filter', '--header', placeholder, '--placeholder', 'Filter...']
      cmd += ['--value', default] if default
      # Pipe options to gum filter
      result = IO.popen(cmd, 'r+') do |io|
        io.puts options.join("\n")
        io.close_write
        io.read.strip
      end
      if result.empty?
        allow_new ? prompt_input("Enter custom value for #{placeholder}", default) : default
      else
        result
      end
    else
      # Fallback to choose
      result = prompt_choose(placeholder, options, default)
      if result == default && allow_new
        prompt_input("Enter custom value for #{placeholder}", default)
      else
        result
      end
    end
  end

  # Prompts with fuzzy filter allowing multiple selections. Returns array.
  def self.prompt_filter_multi(placeholder, options)
    return [] if options.empty?

    if gum_available?
      cmd = ['gum', 'filter', '--no-limit', '--header', "#{placeholder} (tab to select, enter to confirm)", '--placeholder', 'Filter...']
      # Pipe options to gum filter
      result = IO.popen(cmd, 'r+') do |io|
        io.puts options.join("\n")
        io.close_write
        io.read.strip
      end
      result.split("\n").map(&:strip).reject(&:empty?)
    else
      # Fallback to multi-select choose
      fallback_choose_multi(placeholder, options)
    end
  end

  # Prompts for yes/no confirmation.
  def self.prompt_confirm(placeholder, default = nil)
    if gum_available?
      # gum confirm returns exit code 0 for yes, 1 for no
      system('gum', 'confirm', placeholder)
      $?.success?
    else
      default_hint = default.nil? ? '[y/n]' : (default ? '[Y/n]' : '[y/N]')
      print "#{placeholder} #{default_hint}: "
      input = $stdin.gets&.chomp&.downcase || ''
      if input.empty?
        default.nil? ? false : default
      else
        input.start_with?('y')
      end
    end
  end

  # Checks if gum is available.
  def self.gum_available?
    @gum_available ||= system('command -v gum > /dev/null 2>&1')
  end

  # Prints prompt with default hint for fallback mode.
  def self.print_prompt(placeholder, default)
    if default
      print "#{placeholder} [#{default}]: "
    else
      print "#{placeholder}: "
    end
  end
end
