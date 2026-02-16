# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/template_vars'

class TemplateVarsTest < Minitest::Test
  def test_extract_custom_keys_returns_non_standard_keys
    frontmatter = {
      'id' => 'abc123',
      'title' => 'Test Note',
      'type' => 'note',
      'project' => 'Alpha',
      'custom_field' => 'value'
    }

    custom = TemplateVars.extract_custom_keys(frontmatter)

    assert_equal({ 'project' => 'Alpha', 'custom_field' => 'value' }, custom)
    refute custom.key?('id')
    refute custom.key?('title')
    refute custom.key?('type')
  end

  def test_extract_custom_keys_with_empty_hash
    assert_equal({}, TemplateVars.extract_custom_keys({}))
  end

  def test_extract_custom_keys_with_nil
    assert_equal({}, TemplateVars.extract_custom_keys(nil))
  end

  def test_detect_dependencies_finds_erb_variables
    value = '<%= project %>-<%= type %>'
    deps = TemplateVars.detect_dependencies(value)

    assert_includes deps, 'project'
    assert_includes deps, 'type'
  end

  def test_detect_dependencies_finds_method_call_args
    value = '<%= slugify(title) %>'
    deps = TemplateVars.detect_dependencies(value)

    assert_includes deps, 'title'
  end

  def test_detect_dependencies_with_no_erb
    value = 'plain text'
    deps = TemplateVars.detect_dependencies(value)

    assert_empty deps
  end

  def test_build_dependency_graph
    custom_keys = {
      'note_prefix' => '<%= project %>-<%= type %>',
      'full_title' => '<%= note_prefix %>: <%= title %>',
      'project' => 'Alpha'
    }

    graph = TemplateVars.build_dependency_graph(custom_keys)

    assert_includes graph['note_prefix'], 'project'
    assert_includes graph['full_title'], 'note_prefix'
    assert_empty graph['project']
  end

  def test_topological_sort_orders_correctly
    graph = {
      'a' => [],
      'b' => ['a'],
      'c' => ['b']
    }

    order = TemplateVars.topological_sort(graph)

    assert_equal 3, order.size
    assert order.index('a') < order.index('b')
    assert order.index('b') < order.index('c')
  end

  def test_topological_sort_raises_on_cycle
    graph = {
      'a' => ['b'],
      'b' => ['a']
    }

    assert_raises(TemplateVars::CyclicDependencyError) do
      TemplateVars.topological_sort(graph)
    end
  end

  def test_resolve_custom_vars_renders_in_order
    custom_keys = {
      'project' => 'Alpha',
      'note_prefix' => '<%= project %>-note'
    }
    base_vars = { 'type' => 'note' }

    resolved = TemplateVars.resolve_custom_vars(custom_keys, base_vars)

    assert_equal 'Alpha', resolved['project']
    assert_equal 'Alpha-note', resolved['note_prefix']
    assert_equal 'note', resolved['type']
  end

  def test_resolve_custom_vars_with_empty_custom_keys
    base_vars = { 'type' => 'note', 'title' => 'Test' }

    resolved = TemplateVars.resolve_custom_vars({}, base_vars)

    assert_equal base_vars, resolved
  end

  def test_render_erb_value_substitutes_variables
    value = 'Hello <%= name %>'
    vars = { 'name' => 'World' }

    result = TemplateVars.render_erb_value(value, vars)

    assert_equal 'Hello World', result
  end

  def test_render_erb_value_with_slugify
    value = '<%= slugify(title) %>'
    vars = { 'title' => 'Hello World' }
    slugify_proc = ->(text) { text.downcase.gsub(' ', '-') }

    result = TemplateVars.render_erb_value(value, vars, slugify_proc: slugify_proc)

    assert_equal 'hello-world', result
  end

  def test_merge_with_precedence_later_wins
    custom_vars = { 'title' => 'Custom Title', 'project' => 'Alpha' }
    time_vars = { 'date' => '2025-01-01', 'year' => '2025' }

    result = TemplateVars.merge_with_precedence(
      custom_vars, time_vars,
      type: 'note',
      title: 'Explicit Title',
      tags: ['work']
    )

    assert_equal 'Explicit Title', result['title']  # Explicit wins
    assert_equal 'note', result['type']
    assert_equal 'Alpha', result['project']
    assert_equal '2025-01-01', result['date']
    assert_equal ['work'], result['tags']
  end

  def test_merge_with_precedence_skips_empty_title
    custom_vars = { 'title' => 'Custom Title' }
    time_vars = {}

    result = TemplateVars.merge_with_precedence(
      custom_vars, time_vars,
      type: 'note',
      title: '',
      tags: []
    )

    assert_equal 'Custom Title', result['title']  # Custom preserved when explicit is empty
    refute result.key?('tags')  # Empty tags not added
  end
end
