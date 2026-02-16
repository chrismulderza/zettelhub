# frozen_string_literal: true

# Evaluates condition expressions for template prompts.
# Supports: ==, !=, =~, in, &&, ||, and truthy checks (?).
module ConditionEvaluator
  # Pattern for parsing condition expressions.
  # Matches: var == 'value', var != 'value', var =~ /pattern/, var in [...], var?
  EQUALITY_PATTERN = /\A\s*(\w+)\s*(==|!=)\s*['"]([^'"]*)['"]\s*\z/.freeze
  REGEX_PATTERN = /\A\s*(\w+)\s*=~\s*\/([^\/]*)\/\s*\z/.freeze
  IN_PATTERN = /\A\s*(\w+)\s+in\s+\[([^\]]*)\]\s*\z/.freeze
  TRUTHY_PATTERN = /\A\s*(\w+)\?\s*\z/.freeze

  # Evaluates a condition expression against current variables.
  # Returns true if condition is met, false otherwise.
  # Empty or nil condition returns true (always show prompt).
  def self.evaluate(condition, vars)
    return true if condition.nil? || condition.to_s.strip.empty?

    condition = condition.to_s.strip

    # Handle compound expressions: && and ||
    if condition.include?('&&')
      parts = condition.split('&&').map(&:strip)
      return parts.all? { |part| evaluate(part, vars) }
    end

    if condition.include?('||')
      parts = condition.split('||').map(&:strip)
      return parts.any? { |part| evaluate(part, vars) }
    end

    # Single condition evaluation
    evaluate_single(condition, vars)
  end

  # Evaluates a single condition (no && or ||).
  def self.evaluate_single(condition, vars)
    # Truthy check: var?
    if (match = condition.match(TRUTHY_PATTERN))
      var_name = match[1]
      value = vars[var_name]
      return truthy?(value)
    end

    # Equality: var == 'value' or var != 'value'
    if (match = condition.match(EQUALITY_PATTERN))
      var_name, operator, expected = match.captures
      actual = vars[var_name].to_s
      case operator
      when '=='
        return actual == expected
      when '!='
        return actual != expected
      end
    end

    # Regex match: var =~ /pattern/
    if (match = condition.match(REGEX_PATTERN))
      var_name, pattern = match.captures
      actual = vars[var_name].to_s
      return !!(actual =~ Regexp.new(pattern))
    end

    # List membership: var in ['a', 'b', 'c']
    if (match = condition.match(IN_PATTERN))
      var_name, list_str = match.captures
      actual = vars[var_name].to_s
      list = parse_list(list_str)
      return list.include?(actual)
    end

    # Unknown condition format - default to true
    true
  end

  # Checks if a value is truthy (non-nil, non-empty).
  def self.truthy?(value)
    return false if value.nil?
    return false if value.is_a?(String) && value.strip.empty?
    return false if value.is_a?(Array) && value.empty?
    return false if value.is_a?(Hash) && value.empty?
    return false if value == false

    true
  end

  # Parses a list string like "'a', 'b', 'c'" into an array.
  def self.parse_list(list_str)
    list_str.scan(/['"]([^'"]*)['"]/m).flatten
  end
end
