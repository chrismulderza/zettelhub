# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require_relative '../../lib/models/bookmark'

class BookmarkTest < Minitest::Test
  def test_uri_from_metadata
    content = <<~EOF
      ---
      id: bm1
      type: bookmark
      uri: "https://example.com/page"
      title: "Example"
      ---
      # Example
    EOF
    file = Tempfile.new(['bookmark', '.md'])
    file.write(content)
    file.close
    bookmark = Bookmark.new(path: file.path)
    assert_equal 'bm1', bookmark.id
    assert_equal 'bookmark', bookmark.type
    assert_equal 'https://example.com/page', bookmark.uri
  end

  def test_uri_nil_when_missing
    content = <<~EOF
      ---
      id: bm2
      type: bookmark
      title: "No URI"
      ---
      # No URI
    EOF
    file = Tempfile.new(['bookmark', '.md'])
    file.write(content)
    file.close
    bookmark = Bookmark.new(path: file.path)
    assert_nil bookmark.uri
  end

  def test_uri_from_symbol_key
    content = <<~EOF
      ---
      id: bm3
      type: bookmark
      uri: "https://example.org"
      ---
      # Content
    EOF
    file = Tempfile.new(['bookmark', '.md'])
    file.write(content)
    file.close
    bookmark = Bookmark.new(path: file.path, metadata: { uri: 'https://override.org' })
    # File metadata has string key 'uri'; opts merge: file wins. So we get from metadata.
    assert_equal 'https://example.org', bookmark.uri
  end
end
