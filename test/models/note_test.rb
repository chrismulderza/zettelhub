require 'minitest/autorun'
require 'tempfile'
require_relative '../../lib/models/note'

class NoteTest < Minitest::Test
  def test_parse_front_matter
    content = <<~EOF
      ---
      id: 123
      type: general
      ---
      # Title
      Content
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path)
    assert_equal '123', note.id
    assert_equal({'id' => 123, 'type' => 'general'}, note.metadata)
    assert_equal "\n# Title\nContent\n", note.content
  end

  def test_no_front_matter
    content = "# Title\nContent"
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path)
    assert note.id
    assert_equal({}, note.metadata)
    assert_equal content, note.content
  end

  def test_missing_path_raises_error
    assert_raises(ArgumentError, 'path is required') do
      Note.new
    end
  end

  def test_missing_path_with_nil_raises_error
    assert_raises(ArgumentError, 'path is required') do
      Note.new(path: nil)
    end
  end

  def test_nonexistent_file_raises_error
    assert_raises(Errno::ENOENT) do
      Note.new(path: '/nonexistent/path/to/file.md')
    end
  end

  def test_complex_metadata_structures
    content = <<~EOF
      ---
      id: 456
      tags:
        - tag1
        - tag2
        - tag3
      author:
        name: John Doe
        email: john@example.com
      metadata:
        nested:
          deep: value
      ---
      # Title
      Content
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path)
    assert_equal '456', note.id
    assert_equal ['tag1', 'tag2', 'tag3'], note.metadata['tags']
    assert_equal 'John Doe', note.metadata['author']['name']
    assert_equal 'value', note.metadata['metadata']['nested']['deep']
  end

  def test_metadata_with_special_characters
    content = <<~EOF
      ---
      id: 789
      title: "Special: Characters & Symbols \\"quoted\\""
      description: |
        Line 1
        Line 2
      ---
      # Content
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path)
    assert_equal '789', note.id
    assert_equal 'Special: Characters & Symbols "quoted"', note.metadata['title']
    assert_includes note.metadata['description'], 'Line 1'
  end

  def test_id_from_metadata
    content = <<~EOF
      ---
      id: metadata-id-123
      type: general
      ---
      # Title
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path)
    assert_equal 'metadata-id-123', note.id
  end

  def test_id_generated_when_not_in_metadata
    content = <<~EOF
      ---
      type: general
      ---
      # Title
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path)
    assert note.id
    assert_equal 8, note.id.length
  end

  def test_id_from_opts_overrides_metadata
    content = <<~EOF
      ---
      id: metadata-id
      ---
      # Title
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path, id: 'opts-id')
    assert_equal 'opts-id', note.id
  end

  def test_content_with_only_front_matter_no_body
    content = <<~EOF
      ---
      id: 999
      type: general
      ---
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path)
    assert_equal '999', note.id
    assert_equal({ 'id' => 999, 'type' => 'general' }, note.metadata)
    # Body should be empty or whitespace
    assert note.body.nil? || note.body.strip.empty?
  end

  def test_empty_file
    file = Tempfile.new(['note', '.md'])
    file.write('')
    file.close
    note = Note.new(path: file.path)
    assert note.id
    assert_equal({}, note.metadata)
    assert_equal '', note.content
  end

  def test_unicode_and_special_characters_in_content
    content = <<~EOF
      ---
      id: unicode-test
      title: "日本語タイトル"
      ---
      # コンテンツ
      
      Emoji: 🎉 📝 ✨
      
      Special chars: © ® ™ € £ ¥
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path)
    assert_equal 'unicode-test', note.id
    assert_equal '日本語タイトル', note.metadata['title']
    assert_includes note.content, 'コンテンツ'
    assert_includes note.content, '🎉'
    assert_includes note.content, '©'
  end

  def test_metadata_merged_from_opts
    content = <<~EOF
      ---
      id: 111
      type: file-type
      ---
      # Title
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(
      path: file.path,
      metadata: { 'type' => 'opts-type', 'custom' => 'value' }
    )
    # opts metadata is merged with file metadata, but file metadata takes precedence
    # The merge happens as: opts.merge(file_metadata), so file metadata overrides opts
    # This is the actual behavior - file metadata overrides opts metadata
    assert_equal 'file-type', note.metadata['type'] # file metadata overrides opts
    assert_equal 'value', note.metadata['custom'] # opts addition is preserved
    assert_equal 111, note.metadata['id'] # file metadata preserved
  end

  def test_title_from_metadata
    content = <<~EOF
      ---
      id: title-test
      title: "Metadata Title"
      ---
      # Content Title
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path)
    assert_equal 'Metadata Title', note.title
  end

  def test_title_from_opts_overrides_metadata
    content = <<~EOF
      ---
      id: title-test
      title: "Metadata Title"
      ---
      # Content
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path, title: 'Opts Title')
    assert_equal 'Opts Title', note.title
  end

  def test_type_from_metadata
    content = <<~EOF
      ---
      id: type-test
      type: journal
      ---
      # Content
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path)
    assert_equal 'journal', note.type
  end

  def test_date_from_metadata
    content = <<~EOF
      ---
      id: date-test
      date: 2025-01-23
      ---
      # Content
    EOF
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new(path: file.path)
    # Date is parsed as Date object by YAML when using YYYY-MM-DD format
    if note.date.is_a?(Date)
      assert_equal Date.new(2025, 1, 23), note.date
    else
      assert_equal '2025-01-23', note.date
    end
  end

  def test_path_with_string_key
    content = "# Title\nContent"
    file = Tempfile.new(['note', '.md'])
    file.write(content)
    file.close
    note = Note.new('path' => file.path)
    assert note.id
    assert_equal content, note.content
  end
end