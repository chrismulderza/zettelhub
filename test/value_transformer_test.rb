# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/value_transformer'

class ValueTransformerTest < Minitest::Test
  def test_trim_transform
    result = ValueTransformer.apply('  hello  ', 'trim')
    assert_equal 'hello', result
  end

  def test_lowercase_transform
    result = ValueTransformer.apply('Hello World', 'lowercase')
    assert_equal 'hello world', result
  end

  def test_uppercase_transform
    result = ValueTransformer.apply('Hello World', 'uppercase')
    assert_equal 'HELLO WORLD', result
  end

  def test_capitalize_transform
    result = ValueTransformer.apply('hello world', 'capitalize')
    assert_equal 'Hello world', result
  end

  def test_titleize_transform
    result = ValueTransformer.apply('hello world', 'titleize')
    assert_equal 'Hello World', result
  end

  def test_slugify_transform
    result = ValueTransformer.apply('Hello World!', 'slugify')
    assert_equal 'hello-world', result
  end

  def test_strip_prefix_transform
    result = ValueTransformer.apply('client-acme', 'strip_prefix:client-')
    assert_equal 'acme', result
  end

  def test_strip_suffix_transform
    result = ValueTransformer.apply('project-alpha.md', 'strip_suffix:.md')
    assert_equal 'project-alpha', result
  end

  def test_split_transform
    result = ValueTransformer.apply('a, b, c', { 'split' => ',' })
    assert_equal %w[a b c], result
  end

  def test_join_transform
    result = ValueTransformer.apply(%w[a b c], { 'join' => ', ' })
    assert_equal 'a, b, c', result
  end

  def test_default_transform
    result = ValueTransformer.apply('', { 'default' => 'fallback' })
    assert_equal 'fallback', result

    result = ValueTransformer.apply('value', { 'default' => 'fallback' })
    assert_equal 'value', result
  end

  def test_prepend_transform
    result = ValueTransformer.apply('world', { 'prepend' => 'hello ' })
    assert_equal 'hello world', result
  end

  def test_append_transform
    result = ValueTransformer.apply('hello', { 'append' => ' world' })
    assert_equal 'hello world', result
  end

  def test_truncate_transform
    result = ValueTransformer.apply('hello world this is long', { 'truncate' => 15 })
    assert_equal 'hello world ...', result

    result = ValueTransformer.apply('short', { 'truncate' => 15 })
    assert_equal 'short', result
  end

  def test_multiple_transforms
    result = ValueTransformer.apply('  Hello World  ', ['trim', 'lowercase'])
    assert_equal 'hello world', result
  end

  def test_nil_transforms_returns_original
    result = ValueTransformer.apply('hello', nil)
    assert_equal 'hello', result
  end

  def test_empty_transforms_returns_original
    result = ValueTransformer.apply('hello', [])
    assert_equal 'hello', result
  end
end
