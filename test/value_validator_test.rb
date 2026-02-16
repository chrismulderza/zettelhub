# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/value_validator'

class ValueValidatorTest < Minitest::Test
  def test_nil_rules_returns_valid
    result = ValueValidator.validate('anything', nil)
    assert result.valid?
  end

  def test_empty_rules_returns_valid
    result = ValueValidator.validate('anything', {})
    assert result.valid?
  end

  def test_required_with_empty_value
    result = ValueValidator.validate('', { 'required' => true })
    refute result.valid?
    assert_match(/required/i, result.message)
  end

  def test_required_with_value
    result = ValueValidator.validate('hello', { 'required' => true })
    assert result.valid?
  end

  def test_email_validation_valid
    result = ValueValidator.validate('test@example.com', { 'type' => 'email' })
    assert result.valid?
  end

  def test_email_validation_invalid
    result = ValueValidator.validate('not-an-email', { 'type' => 'email' })
    refute result.valid?
    assert_match(/email/i, result.message)
  end

  def test_url_validation_valid
    result = ValueValidator.validate('https://example.com', { 'type' => 'url' })
    assert result.valid?
  end

  def test_url_validation_invalid
    result = ValueValidator.validate('not-a-url', { 'type' => 'url' })
    refute result.valid?
    assert_match(/url/i, result.message)
  end

  def test_date_validation_valid
    result = ValueValidator.validate('2025-01-15', { 'type' => 'date' })
    assert result.valid?
  end

  def test_date_validation_invalid
    result = ValueValidator.validate('not-a-date', { 'type' => 'date' })
    refute result.valid?
    assert_match(/date/i, result.message)
  end

  def test_id_validation_valid
    result = ValueValidator.validate('abc12345', { 'type' => 'id' })
    assert result.valid?
  end

  def test_id_validation_invalid
    result = ValueValidator.validate('xyz', { 'type' => 'id' })
    refute result.valid?
  end

  def test_slug_validation_valid
    result = ValueValidator.validate('hello-world', { 'type' => 'slug' })
    assert result.valid?
  end

  def test_slug_validation_invalid
    result = ValueValidator.validate('Hello World!', { 'type' => 'slug' })
    refute result.valid?
  end

  def test_pattern_validation_valid
    result = ValueValidator.validate('AB-1234', { 'pattern' => '^[A-Z]{2}-\d{4}$' })
    assert result.valid?
  end

  def test_pattern_validation_invalid
    result = ValueValidator.validate('invalid', { 'pattern' => '^[A-Z]{2}-\d{4}$' })
    refute result.valid?
  end

  def test_min_length_validation
    result = ValueValidator.validate('ab', { 'min_length' => 3 })
    refute result.valid?

    result = ValueValidator.validate('abc', { 'min_length' => 3 })
    assert result.valid?
  end

  def test_max_length_validation
    result = ValueValidator.validate('abcdef', { 'max_length' => 5 })
    refute result.valid?

    result = ValueValidator.validate('abc', { 'max_length' => 5 })
    assert result.valid?
  end

  def test_custom_error_message
    result = ValueValidator.validate('', { 'required' => true, 'message' => 'Custom error' })
    refute result.valid?
    assert_equal 'Custom error', result.message
  end

  def test_empty_value_skips_validation_when_not_required
    result = ValueValidator.validate('', { 'type' => 'email' })
    assert result.valid?
  end
end
