require 'minitest/autorun'
require_relative '../../lib/models/document'

class DocumentTest < Minitest::Test
  def test_generate_id_creates_unique_ids
    id1 = Document.generate_id
    id2 = Document.generate_id
    assert id1 != id2, 'IDs should be unique'
  end

  def test_generate_id_length
    id = Document.generate_id
    assert_equal 8, id.length, 'ID should be 8 characters (4 bytes hex)'
  end

  def test_generate_id_format
    id = Document.generate_id
    assert_match(/^[0-9a-f]{8}$/, id, 'ID should be hexadecimal')
  end

  def test_initialize_with_symbol_keys
    doc = Document.new(
      id: 'test123',
      title: 'Test Title',
      type: 'test',
      path: '/path/to/file',
      date: '2025-01-01',
      content: 'Content',
      metadata: { 'key' => 'value' },
      body: 'Body'
    )
    assert_equal 'test123', doc.id
    assert_equal 'Test Title', doc.title
    assert_equal 'test', doc.type
    assert_equal '/path/to/file', doc.path
    assert_equal '2025-01-01', doc.date
    assert_equal 'Content', doc.content
    assert_equal({ 'key' => 'value' }, doc.metadata)
    assert_equal 'Body', doc.body
  end

  def test_initialize_with_string_keys
    doc = Document.new(
      'id' => 'test456',
      'title' => 'Test Title 2',
      'type' => 'test2',
      'path' => '/path/to/file2',
      'date' => '2025-01-02',
      'content' => 'Content 2',
      'metadata' => { 'key2' => 'value2' },
      'body' => 'Body 2'
    )
    assert_equal 'test456', doc.id
    assert_equal 'Test Title 2', doc.title
    assert_equal 'test2', doc.type
    assert_equal '/path/to/file2', doc.path
    assert_equal '2025-01-02', doc.date
    assert_equal 'Content 2', doc.content
    assert_equal({ 'key2' => 'value2' }, doc.metadata)
    assert_equal 'Body 2', doc.body
  end

  def test_initialize_without_id_generates_one
    doc = Document.new
    assert doc.id
    assert_equal 8, doc.id.length
  end

  def test_initialize_with_nil_id_uses_nil
    # When id key is present but nil, it uses nil (doesn't generate)
    doc = Document.new(id: nil)
    assert_nil doc.id
  end

  def test_initialize_with_empty_hash
    doc = Document.new({})
    assert doc.id
    assert_nil doc.title
    assert_nil doc.type
    assert_nil doc.path
    assert_nil doc.date
    assert_nil doc.content
    assert_equal({}, doc.metadata)
    assert_nil doc.body
  end

  def test_initialize_with_partial_attributes
    doc = Document.new(title: 'Title Only')
    assert doc.id
    assert_equal 'Title Only', doc.title
    assert_nil doc.type
    assert_nil doc.path
    assert_nil doc.date
    assert_nil doc.content
    assert_equal({}, doc.metadata)
    assert_nil doc.body
  end

  def test_initialize_with_empty_metadata_defaults_to_empty_hash
    doc = Document.new(metadata: nil)
    assert_equal({}, doc.metadata)
  end

  def test_initialize_without_metadata_defaults_to_empty_hash
    doc = Document.new
    assert_equal({}, doc.metadata)
  end

  def test_initialize_with_complex_metadata
    complex_metadata = {
      'tags' => ['tag1', 'tag2'],
      'nested' => { 'key' => 'value' },
      'number' => 42,
      'boolean' => true
    }
    doc = Document.new(metadata: complex_metadata)
    assert_equal complex_metadata, doc.metadata
  end

  def test_attribute_accessors
    doc = Document.new(
      id: 'accessor_test',
      title: 'Accessor Title',
      type: 'accessor_type',
      path: '/accessor/path',
      date: '2025-01-03',
      content: 'Accessor Content',
      metadata: { 'test' => true },
      body: 'Accessor Body'
    )
    assert_equal 'accessor_test', doc.id
    assert_equal 'Accessor Title', doc.title
    assert_equal 'accessor_type', doc.type
    assert_equal '/accessor/path', doc.path
    assert_equal '2025-01-03', doc.date
    assert_equal 'Accessor Content', doc.content
    assert_equal({ 'test' => true }, doc.metadata)
    assert_equal 'Accessor Body', doc.body
  end

  def test_initialize_with_mixed_key_types
    # This should normalize string keys to symbols
    doc = Document.new(
      'id' => 'mixed1',
      :title => 'Mixed Title',
      'type' => 'mixed_type'
    )
    assert_equal 'mixed1', doc.id
    assert_equal 'Mixed Title', doc.title
    assert_equal 'mixed_type', doc.type
  end
end
