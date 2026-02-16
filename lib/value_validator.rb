# frozen_string_literal: true

require 'uri'
require 'date'

# Validates prompt values against defined rules.
# Supports built-in validators (url, email, date, id, slug) and custom regex patterns.
module ValueValidator
  # Built-in validation patterns.
  PATTERNS = {
    'email' => /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i,
    'id' => /\A[a-f0-9]{6,12}\z/i,
    'slug' => /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
    'alphanumeric' => /\A[a-zA-Z0-9]+\z/,
    'numeric' => /\A\d+\z/
  }.freeze

  # Result of validation: success or failure with message.
  ValidationResult = Struct.new(:valid, :message, keyword_init: true) do
    def valid?
      valid
    end
  end

  # Validates a value against validation rules.
  # Returns ValidationResult with valid? and message.
  def self.validate(value, rules)
    return ValidationResult.new(valid: true) if rules.nil? || rules.empty?

    rules = { 'type' => rules } if rules.is_a?(String)

    # Check required first
    if rules['required'] && (value.nil? || value.to_s.strip.empty?)
      message = rules['message'] || 'This field is required'
      return ValidationResult.new(valid: false, message: message)
    end

    # Skip further validation if value is empty and not required
    return ValidationResult.new(valid: true) if value.to_s.strip.empty?

    # Type-based validation
    if rules['type']
      result = validate_type(value, rules['type'])
      return result unless result.valid?
    end

    # Pattern-based validation
    if rules['pattern']
      result = validate_pattern(value, rules['pattern'], rules['message'])
      return result unless result.valid?
    end

    # Min/max length
    if rules['min_length']
      if value.to_s.length < rules['min_length'].to_i
        message = rules['message'] || "Minimum length is #{rules['min_length']}"
        return ValidationResult.new(valid: false, message: message)
      end
    end

    if rules['max_length']
      if value.to_s.length > rules['max_length'].to_i
        message = rules['message'] || "Maximum length is #{rules['max_length']}"
        return ValidationResult.new(valid: false, message: message)
      end
    end

    ValidationResult.new(valid: true)
  end

  # Validates value against a built-in type.
  def self.validate_type(value, type)
    case type.to_s.downcase
    when 'url'
      validate_url(value)
    when 'email'
      validate_pattern(value, PATTERNS['email'], 'Invalid email address')
    when 'date'
      validate_date(value)
    when 'id'
      validate_pattern(value, PATTERNS['id'], 'Invalid ID format (expected 6-12 hex characters)')
    when 'slug'
      validate_pattern(value, PATTERNS['slug'], 'Invalid slug format (lowercase letters, numbers, hyphens)')
    when 'alphanumeric'
      validate_pattern(value, PATTERNS['alphanumeric'], 'Only letters and numbers allowed')
    when 'numeric'
      validate_pattern(value, PATTERNS['numeric'], 'Only numbers allowed')
    else
      ValidationResult.new(valid: true)
    end
  end

  # Validates a URL.
  def self.validate_url(value)
    uri = URI.parse(value.to_s)
    if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      ValidationResult.new(valid: true)
    else
      ValidationResult.new(valid: false, message: 'Invalid URL (must start with http:// or https://)')
    end
  rescue URI::InvalidURIError
    ValidationResult.new(valid: false, message: 'Invalid URL format')
  end

  # Validates a date string.
  def self.validate_date(value)
    Date.parse(value.to_s)
    ValidationResult.new(valid: true)
  rescue ArgumentError
    ValidationResult.new(valid: false, message: 'Invalid date format')
  end

  # Validates value against a regex pattern.
  def self.validate_pattern(value, pattern, message = nil)
    regex = pattern.is_a?(Regexp) ? pattern : Regexp.new(pattern.to_s)
    if value.to_s.match?(regex)
      ValidationResult.new(valid: true)
    else
      ValidationResult.new(valid: false, message: message || "Value does not match required pattern")
    end
  end
end
