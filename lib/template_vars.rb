# frozen_string_literal: true

require 'erb'

# Template variable resolution with dependency ordering.
# Resolves custom template variables that can reference each other.
module TemplateVars
  # Raised when cyclic dependencies are detected between template variables.
  class CyclicDependencyError < StandardError; end

  # Raised when a variable references an undefined variable.
  class UndefinedVariableError < StandardError; end

  # Standard front matter keys that are not custom template variables.
  STANDARD_FRONTMATTER_KEYS = %w[id type date title aliases tags description config content].freeze

  # Time-related variables provided by Utils.current_time_vars.
  TIME_VAR_KEYS = %w[
    date year month week week_year month_name month_name_short
    day_name day_name_short time time_iso hour minute second timestamp id
  ].freeze

  # Standard config keys within the config block.
  STANDARD_CONFIG_KEYS = %w[path default_alias default_tags prompts].freeze

  # Pattern to detect ERB variable references: <%= var %> or <%= method(var) %>
  ERB_VAR_PATTERN = /<%=\s*([a-z_][a-z0-9_]*)\s*%>/i

  # Pattern to detect ERB method calls with variable arguments: <%= method(var) %>
  ERB_METHOD_CALL_PATTERN = /<%=\s*\w+\s*\(\s*([a-z_][a-z0-9_]*)\s*\)\s*%>/i

  # Extracts custom keys from front matter (excludes standard and time keys).
  # Returns hash of key => value for non-standard keys.
  def self.extract_custom_keys(frontmatter)
    return {} unless frontmatter.is_a?(Hash)

    custom = {}
    frontmatter.each do |key, value|
      key_s = key.to_s
      next if STANDARD_FRONTMATTER_KEYS.include?(key_s)
      next if TIME_VAR_KEYS.include?(key_s)

      custom[key_s] = value
    end
    custom
  end

  # Detects variable dependencies in a value string.
  # Returns array of variable names referenced via ERB.
  def self.detect_dependencies(value)
    return [] unless value.is_a?(String)

    deps = []
    # Direct variable references: <%= var %>
    value.scan(ERB_VAR_PATTERN) { |match| deps << match[0] }
    # Method call arguments: <%= slugify(var) %>
    value.scan(ERB_METHOD_CALL_PATTERN) { |match| deps << match[0] }
    deps.uniq
  end

  # Builds dependency graph from custom keys.
  # Returns hash of key => [dependency_keys].
  def self.build_dependency_graph(custom_keys)
    graph = {}
    custom_keys.each do |key, value|
      deps = detect_dependencies(value.to_s)
      # Only include dependencies that are custom keys (not time vars or standard)
      graph[key] = deps.select { |d| custom_keys.key?(d) }
    end
    graph
  end

  # Topological sort of dependency graph using Kahn's algorithm.
  # Returns ordered array of keys to process, or raises CyclicDependencyError.
  # graph[node] contains list of nodes that `node` depends on.
  def self.topological_sort(graph)
    # In-degree = number of dependencies for each node
    in_degree = {}
    graph.each do |node, deps|
      in_degree[node] ||= 0
      in_degree[node] = deps.size
    end

    # Find nodes with no dependencies (in_degree == 0)
    queue = graph.keys.select { |node| in_degree[node].zero? }
    result = []

    until queue.empty?
      node = queue.shift
      result << node

      # For each node that depends on 'node', reduce its in-degree
      graph.each do |dependent, deps|
        next unless deps.include?(node)

        in_degree[dependent] -= 1
        queue << dependent if in_degree[dependent].zero?
      end
    end

    # Check for cycles
    if result.size != graph.size
      missing = graph.keys - result
      raise CyclicDependencyError, "Cyclic dependency detected involving: #{missing.join(', ')}"
    end

    result
  end

  # Resolves custom variables in dependency order.
  # base_vars provides initial values (time vars, type, title, etc.).
  # Returns hash of all resolved variables.
  def self.resolve_custom_vars(custom_keys, base_vars, slugify_proc: nil)
    return base_vars.dup if custom_keys.empty?

    graph = build_dependency_graph(custom_keys)
    order = topological_sort(graph)

    resolved = base_vars.dup

    order.each do |key|
      value = custom_keys[key]
      if value.is_a?(String) && value.include?('<%')
        # Render ERB with current resolved values
        resolved[key] = render_erb_value(value, resolved, slugify_proc: slugify_proc)
      else
        resolved[key] = value
      end
    end

    resolved
  end

  # Renders a single ERB value string with given variables.
  def self.render_erb_value(value, vars, slugify_proc: nil)
    return value unless value.is_a?(String) && value.include?('<%')

    template = ERB.new(value)
    context = ErbContext.new(vars, slugify_proc: slugify_proc)
    template.result(context.get_binding)
  rescue NameError => e
    # Extract undefined variable name from error
    match = e.message.match(/undefined local variable or method `(\w+)'/)
    var_name = match ? match[1] : 'unknown'
    raise UndefinedVariableError, "Undefined variable '#{var_name}' in template: #{value}"
  end

  # Merges resolved custom vars with standard vars following precedence rules.
  # Later values win: custom_vars < time_vars < explicit args (type, title, tags).
  def self.merge_with_precedence(custom_vars, time_vars, type:, title:, tags:, description: nil)
    vars = {}
    vars.merge!(custom_vars)
    vars.merge!(time_vars)
    vars['type'] = type
    vars['title'] = title unless title.to_s.empty?
    vars['tags'] = tags unless tags.nil? || (tags.is_a?(Array) && tags.empty?)
    vars['description'] = description.to_s unless description.to_s.empty?
    vars
  end

  # ERB binding context that provides variables and helper methods.
  class ErbContext
    def initialize(vars, slugify_proc: nil)
      @vars = vars
      @slugify_proc = slugify_proc || ->(text) { Utils.slugify(text) }

      # Define accessor methods for each variable
      @vars.each do |key, value|
        define_singleton_method(key.to_sym) { value }
      end
    end

    # Helper method for slugifying text.
    def slugify(text)
      @slugify_proc.call(text)
    end

    # Returns the binding for ERB evaluation.
    def get_binding
      binding
    end

    # Handles undefined variables gracefully.
    def method_missing(method_name, *args)
      return '' if args.empty? # Return empty string for undefined vars
      super
    end

    def respond_to_missing?(method_name, include_private = false)
      true # Accept any method to handle undefined vars
    end
  end
end
