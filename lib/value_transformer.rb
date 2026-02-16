# frozen_string_literal: true

require_relative 'utils'

# Applies transformations to prompt values.
# Supports: trim, lowercase, uppercase, slugify, split, join, strip_prefix, strip_suffix.
module ValueTransformer
  # Applies a list of transformations to a value.
  # Transforms can be strings ('trim', 'lowercase') or hashes ({ 'split' => ',' }).
  def self.apply(value, transforms)
    return value if transforms.nil? || transforms.empty?

    transforms = [transforms] unless transforms.is_a?(Array)
    result = value

    transforms.each do |transform|
      result = apply_single(result, transform)
    end

    result
  end

  # Applies a single transformation.
  def self.apply_single(value, transform)
    case transform
    when String
      apply_string_transform(value, transform)
    when Hash
      apply_hash_transform(value, transform)
    else
      value
    end
  end

  # Applies a named string transformation.
  def self.apply_string_transform(value, name)
    case name.downcase
    when 'trim'
      value.to_s.strip
    when 'lowercase', 'downcase'
      value.to_s.downcase
    when 'uppercase', 'upcase'
      value.to_s.upcase
    when 'slugify'
      Utils.slugify(value.to_s)
    when 'capitalize'
      value.to_s.capitalize
    when 'titleize'
      value.to_s.split.map(&:capitalize).join(' ')
    else
      # Check for strip_prefix:X or strip_suffix:X format
      if name.start_with?('strip_prefix:')
        prefix = name.sub('strip_prefix:', '')
        value.to_s.sub(/\A#{Regexp.escape(prefix)}/, '')
      elsif name.start_with?('strip_suffix:')
        suffix = name.sub('strip_suffix:', '')
        value.to_s.sub(/#{Regexp.escape(suffix)}\z/, '')
      else
        value
      end
    end
  end

  # Applies a hash-based transformation (e.g., { 'split' => ',' }).
  def self.apply_hash_transform(value, transform_hash)
    transform_hash.each do |op, arg|
      case op.to_s.downcase
      when 'split'
        return value.to_s.split(arg).map(&:strip)
      when 'join'
        return value.is_a?(Array) ? value.join(arg) : value.to_s
      when 'replace'
        # arg should be [pattern, replacement]
        if arg.is_a?(Array) && arg.size == 2
          return value.to_s.gsub(arg[0], arg[1])
        end
      when 'default'
        return value.to_s.empty? ? arg : value
      when 'prepend'
        return "#{arg}#{value}"
      when 'append'
        return "#{value}#{arg}"
      when 'truncate'
        max_len = arg.to_i
        return value.to_s.length > max_len ? "#{value.to_s[0, max_len - 3]}..." : value.to_s
      end
    end

    value
  end
end
