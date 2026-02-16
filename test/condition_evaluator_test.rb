# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/condition_evaluator'

class ConditionEvaluatorTest < Minitest::Test
  def test_nil_condition_returns_true
    assert ConditionEvaluator.evaluate(nil, {})
  end

  def test_empty_condition_returns_true
    assert ConditionEvaluator.evaluate('', {})
    assert ConditionEvaluator.evaluate('   ', {})
  end

  def test_equality_operator
    vars = { 'type' => 'meeting' }

    assert ConditionEvaluator.evaluate("type == 'meeting'", vars)
    refute ConditionEvaluator.evaluate("type == 'note'", vars)
  end

  def test_inequality_operator
    vars = { 'status' => 'draft' }

    assert ConditionEvaluator.evaluate("status != 'published'", vars)
    refute ConditionEvaluator.evaluate("status != 'draft'", vars)
  end

  def test_regex_match_operator
    vars = { 'title' => 'WIP: Draft' }

    assert ConditionEvaluator.evaluate('title =~ /^WIP/', vars)
    refute ConditionEvaluator.evaluate('title =~ /^DONE/', vars)
  end

  def test_in_operator
    vars = { 'type' => 'meeting' }

    assert ConditionEvaluator.evaluate("type in ['note', 'meeting']", vars)
    refute ConditionEvaluator.evaluate("type in ['note', 'journal']", vars)
  end

  def test_truthy_operator
    vars = { 'project' => 'Alpha', 'empty' => '', 'nil_val' => nil }

    assert ConditionEvaluator.evaluate('project?', vars)
    refute ConditionEvaluator.evaluate('empty?', vars)
    refute ConditionEvaluator.evaluate('nil_val?', vars)
    refute ConditionEvaluator.evaluate('missing?', vars)
  end

  def test_and_operator
    vars = { 'type' => 'meeting', 'project' => 'Alpha' }

    assert ConditionEvaluator.evaluate("type == 'meeting' && project?", vars)
    refute ConditionEvaluator.evaluate("type == 'note' && project?", vars)
  end

  def test_or_operator
    vars = { 'type' => 'meeting' }

    assert ConditionEvaluator.evaluate("type == 'note' || type == 'meeting'", vars)
    refute ConditionEvaluator.evaluate("type == 'note' || type == 'journal'", vars)
  end

  def test_truthy_with_array
    assert ConditionEvaluator.truthy?(['item'])
    refute ConditionEvaluator.truthy?([])
  end

  def test_truthy_with_hash
    assert ConditionEvaluator.truthy?({ key: 'value' })
    refute ConditionEvaluator.truthy?({})
  end

  def test_truthy_with_boolean
    assert ConditionEvaluator.truthy?(true)
    refute ConditionEvaluator.truthy?(false)
  end

  def test_parse_list
    list = ConditionEvaluator.parse_list("'a', 'b', 'c'")
    assert_equal %w[a b c], list

    list = ConditionEvaluator.parse_list('"a", "b"')
    assert_equal %w[a b], list
  end
end
