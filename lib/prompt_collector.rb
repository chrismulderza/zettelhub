# frozen_string_literal: true

require_relative 'condition_evaluator'
require_relative 'prompt_executor'
require_relative 'value_validator'

# Collects values from template prompts with condition evaluation.
module PromptCollector
  # Collects all prompt values from a template's config.prompts.
  # Returns hash of key => value.
  # prompt_defs: array of prompt definitions from template.
  # config: ZettelHub config.
  # initial_vars: pre-existing variables (time vars, type, etc.).
  # provided_values: values already provided via CLI args (skip prompting).
  def self.collect(prompt_defs, config, initial_vars = {}, provided_values = {})
    return {} if prompt_defs.nil? || prompt_defs.empty?

    vars = initial_vars.dup
    collected = {}

    prompt_defs.each do |prompt_def|
      key = prompt_def['key']
      next unless key

      # Skip if value already provided via CLI
      if provided_values.key?(key)
        collected[key] = provided_values[key]
        vars[key] = provided_values[key]
        next
      end

      # Skip hidden prompts (computed values)
      if prompt_def['hidden']
        if prompt_def['default']
          value = PromptExecutor.resolve_default(prompt_def['default'], vars)
          collected[key] = value
          vars[key] = value
        end
        next
      end

      # Check condition
      condition = prompt_def['when']
      unless ConditionEvaluator.evaluate(condition, vars)
        # Condition not met - use default or skip
        if prompt_def['default']
          value = PromptExecutor.resolve_default(prompt_def['default'], vars)
          collected[key] = value
          vars[key] = value
        end
        next
      end

      # For optional prompts, ask for confirmation first
      if prompt_def['optional']
        prompt_label = prompt_def['prompt'] || prompt_def['label'] || key
        unless PromptExecutor.prompt_confirm("Add #{prompt_label}?", false)
          # User declined - use default or nil
          default_value = prompt_def['default'] ? PromptExecutor.resolve_default(prompt_def['default'], vars) : nil
          # For multi-select prompts, default to empty array
          default_value = [] if prompt_def['multi'] && default_value.nil?
          collected[key] = default_value
          vars[key] = default_value
          next
        end
      end

      # Execute prompt with validation loop
      value = prompt_with_validation(prompt_def, config, vars)
      collected[key] = value
      vars[key] = value
    end

    collected
  end

  # Prompts for a value with validation, retrying on invalid input.
  def self.prompt_with_validation(prompt_def, config, vars, max_attempts: 3)
    validation = prompt_def['validate']
    required = prompt_def['required']
    multi = prompt_def['multi'] == true

    max_attempts.times do
      value = PromptExecutor.execute(prompt_def, config, vars)

      # Check required - for multi-select, empty array counts as empty
      value_empty = multi ? (value.nil? || value.empty?) : (value.nil? || value.to_s.strip.empty?)
      if required && value_empty
        puts "This field is required. Please enter a value."
        next
      end

      # Skip validation if empty and not required
      return value if value_empty && !required

      # Validate if rules are specified
      if validation
        result = ValueValidator.validate(value, validation)
        unless result.valid?
          puts "Invalid: #{result.message}"
          next
        end
        return value if result.valid?
      else
        return value
      end
    end

    # Return default after max attempts (empty array for multi-select)
    multi ? [] : prompt_def['default']
  end

  # Collects values non-interactively using defaults and provided values.
  # Used for testing or scripted note creation.
  def self.collect_non_interactive(prompt_defs, initial_vars = {}, provided_values = {})
    return {} if prompt_defs.nil? || prompt_defs.empty?

    vars = initial_vars.dup
    collected = {}

    prompt_defs.each do |prompt_def|
      key = prompt_def['key']
      next unless key

      value = if provided_values.key?(key)
                provided_values[key]
              elsif prompt_def['default']
                PromptExecutor.resolve_default(prompt_def['default'], vars)
              else
                nil
              end

      collected[key] = value
      vars[key] = value
    end

    collected
  end
end
