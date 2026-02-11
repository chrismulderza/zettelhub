# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../../lib/models/resource'

class ResourceTest < Minitest::Test
  def test_parse_front_matter
    content = <<~EOF
      ---
      id: res123
      type: article
      title: "An Article"
      ---
      # Body
    EOF
    file = Tempfile.new(['resource', '.md'])
    file.write(content)
    file.close
    resource = Resource.new(path: file.path)
    assert_equal 'res123', resource.id
    assert_equal 'article', resource.type
    assert_equal 'An Article', resource.title
    assert_equal({ 'id' => 'res123', 'type' => 'article', 'title' => 'An Article' }, resource.metadata)
  end

  def test_missing_path_raises_error
    assert_raises(ArgumentError, 'path is required') do
      Resource.new
    end
  end

  def test_date_optional_nil
    content = <<~EOF
      ---
      id: no-date
      type: resource
      ---
      Content
    EOF
    file = Tempfile.new(['resource', '.md'])
    file.write(content)
    file.close
    resource = Resource.new(path: file.path)
    assert_equal 'no-date', resource.id
    assert_nil resource.date
  end
end
