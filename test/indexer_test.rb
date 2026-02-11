require 'minitest/autorun'
require 'stringio'
require 'tempfile'
require 'fileutils'
require 'sqlite3'
require_relative '../lib/indexer'
require_relative '../lib/models/note'

class IndexerTest < Minitest::Test
  def setup
    @temp_dir = Dir.mktmpdir
    @config = { 'notebook_path' => @temp_dir }
    @indexer = Indexer.new(@config)
    @db_path = File.join(@temp_dir, '.zh', 'index.db')
  end

  def teardown
    FileUtils.rm_rf(@temp_dir)
  end

  def test_index_note
    content = <<~EOF
      ---
      id: 123
      type: general
      title: Test Note
      ---
      # Title
      Content
    EOF
    note_path = File.join(@temp_dir, 'test-note.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT id, path, metadata, title, body, filename FROM notes WHERE id = ?', ['123'])
    assert_equal 1, result.length
    assert_equal '123', result[0][0]
    assert_equal 'test-note.md', result[0][1]
    assert_includes result[0][2], '"id":123'
    assert_equal 'Test Note', result[0][3]
    assert_includes result[0][4], 'Content'
    assert_equal 'test-note.md', result[0][5]
    db.close
  end

  def test_index_note_replaces_existing
    content = <<~EOF
      ---
      id: 456
      type: general
      ---
      # Original
    EOF
    note_path = File.join(@temp_dir, 'test-note.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    updated_content = <<~EOF
      ---
      id: 456
      type: updated
      ---
      # Updated
    EOF
    File.write(note_path, updated_content)
    updated_note = Note.new(path: note_path)
    @indexer.index_note(updated_note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT id, metadata, body FROM notes WHERE id = ?', ['456'])
    assert_equal 1, result.length
    assert_includes result[0][1], '"type":"updated"'
    assert_includes result[0][2], 'Updated'
    db.close
  end

  def test_fts_index_created
    content = <<~EOF
      ---
      id: 789
      type: general
      title: FTS Test
      ---
      # FTS Test Note
      This is test content for full-text search.
    EOF
    note_path = File.join(@temp_dir, 'fts-test.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    
    db = SQLite3::Database.new(@db_path)
    # Check that FTS table exists
    tables = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='notes_fts'")
    assert_equal 1, tables.length
    
    # Check that triggers exist
    triggers = db.execute("SELECT name FROM sqlite_master WHERE type='trigger'")
    trigger_names = triggers.map(&:first)
    assert_includes trigger_names, 'fts_insert'
    assert_includes trigger_names, 'fts_update'
    assert_includes trigger_names, 'fts_delete'
    db.close
  end

  def test_fts_search_title
    content = <<~EOF
      ---
      id: search1
      type: general
      title: Unique Search Title
      ---
      # Content
      Some body text here.
    EOF
    note_path = File.join(@temp_dir, 'search1.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    
    db = SQLite3::Database.new(@db_path)
    results = db.execute(
      "SELECT id FROM notes_fts WHERE notes_fts MATCH 'Unique'"
    )
    assert_equal 1, results.length
    assert_equal 'search1', results[0][0]
    db.close
  end

  def test_fts_search_body
    content = <<~EOF
      ---
      id: search2
      type: general
      title: Another Note
      ---
      # Content
      This note contains the word elephant in the body.
    EOF
    note_path = File.join(@temp_dir, 'search2.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    
    db = SQLite3::Database.new(@db_path)
    results = db.execute(
      "SELECT id FROM notes_fts WHERE notes_fts MATCH 'elephant'"
    )
    assert_equal 1, results.length
    assert_equal 'search2', results[0][0]
    db.close
  end

  def test_fts_search_description
    content = <<~EOF
      ---
      id: search_desc
      type: general
      title: Note Title
      description: >
        This note has a unique phrase only in description: xylophonewidget.
      ---
      # Content
      Some body text here.
    EOF
    note_path = File.join(@temp_dir, 'search-desc.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)

    db = SQLite3::Database.new(@db_path)
    results = db.execute(
      "SELECT id FROM notes_fts WHERE notes_fts MATCH 'xylophonewidget'"
    )
    assert_equal 1, results.length, 'Description text should be searchable in FTS'
    assert_equal 'search_desc', results[0][0]
    db.close
  end

  def test_fts_search_filename
    content = <<~EOF
      ---
      id: search3
      type: general
      title: Filename Test
      ---
      # Content
      Some content.
    EOF
    note_path = File.join(@temp_dir, 'special_filename.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    
    db = SQLite3::Database.new(@db_path)
    results = db.execute(
      "SELECT id FROM notes_fts WHERE notes_fts MATCH 'special_filename'"
    )
    assert_equal 1, results.length
    assert_equal 'search3', results[0][0]
    db.close
  end

  def test_fts_update_on_replace
    content = <<~EOF
      ---
      id: update1
      type: general
      title: Original Title
      ---
      # Original Content
      This is the original body text that should be replaced.
    EOF
    note_path = File.join(@temp_dir, 'update1.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    
    # Update the note
    updated_content = <<~EOF
      ---
      id: update1
      type: general
      title: Updated Title
      ---
      # Updated Content
      This is the updated body text with completely new words.
    EOF
    File.write(note_path, updated_content)
    updated_note = Note.new(path: note_path)
    @indexer.index_note(updated_note)
    
    db = SQLite3::Database.new(@db_path)
    # Search for old content - should not find (using a unique word from old content)
    old_results = db.execute(
      "SELECT id FROM notes_fts WHERE notes_fts MATCH 'replaced'"
    )
    assert_equal 0, old_results.length, 'Old content should not be found after update'
    
    # Search for new content - should find
    new_results = db.execute(
      "SELECT id FROM notes_fts WHERE notes_fts MATCH 'completely'"
    )
    assert_equal 1, new_results.length
    assert_equal 'update1', new_results[0][0]
    
    # Search for new body text
    body_results = db.execute(
      "SELECT id FROM notes_fts WHERE notes_fts MATCH 'new words'"
    )
    assert_equal 1, body_results.length
    db.close
  end

  def test_fts_delete_trigger
    content = <<~EOF
      ---
      id: delete1
      type: general
      title: To Be Deleted
      ---
      # Content
      This will be deleted.
    EOF
    note_path = File.join(@temp_dir, 'delete1.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    
    db = SQLite3::Database.new(@db_path)
    # Verify it's in FTS
    results = db.execute(
      "SELECT id FROM notes_fts WHERE notes_fts MATCH 'Deleted'"
    )
    assert_equal 1, results.length
    
    # Delete from notes table
    db.execute("DELETE FROM notes WHERE id = 'delete1'")
    
    # Verify it's removed from FTS
    results_after = db.execute(
      "SELECT id FROM notes_fts WHERE notes_fts MATCH 'Deleted'"
    )
    assert_equal 0, results_after.length
    db.close
  end

  def test_remove_notes_deletes_from_index_and_fts
    content1 = <<~EOF
      ---
      id: remove1
      type: general
      title: First Note
      ---
      # First
      UniqueContentFirst
    EOF
    content2 = <<~EOF
      ---
      id: remove2
      type: general
      title: Second Note
      ---
      # Second
      UniqueContentSecond
    EOF
    File.write(File.join(@temp_dir, 'remove1.md'), content1)
    File.write(File.join(@temp_dir, 'remove2.md'), content2)
    @indexer.index_note(Note.new(path: File.join(@temp_dir, 'remove1.md')))
    @indexer.index_note(Note.new(path: File.join(@temp_dir, 'remove2.md')))

    @indexer.remove_notes(['remove1'])

    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT id FROM notes ORDER BY id')
    assert_equal 1, result.length
    assert_equal 'remove2', result[0][0]
    # FTS: first note content gone, second still searchable
    assert_equal 0, db.execute("SELECT id FROM notes_fts WHERE notes_fts MATCH 'UniqueContentFirst'").length
    assert_equal 1, db.execute("SELECT id FROM notes_fts WHERE notes_fts MATCH 'UniqueContentSecond'").length
    db.close
  end

  def test_index_note_with_nil_title_and_body
    content = <<~EOF
      ---
      id: nil-test
      type: general
      ---
    EOF
    note_path = File.join(@temp_dir, 'nil-test.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT id, title, body FROM notes WHERE id = ?', ['nil-test'])
    assert_equal 1, result.length
    # title and body may be empty string or just whitespace
    assert result[0][1].nil? || result[0][1].strip.empty?
    assert result[0][2].nil? || result[0][2].strip.empty?
    db.close
  end

  def test_index_note_with_very_long_content
    long_body = 'x' * 10_000
    content = <<~EOF
      ---
      id: long-test
      type: general
      title: Long Content Test
      ---
      #{long_body}
    EOF
    note_path = File.join(@temp_dir, 'long-test.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT LENGTH(body) FROM notes WHERE id = ?', ['long-test'])
    assert result[0][0] >= 10_000, 'Long content should be stored'
    db.close
  end

  def test_index_note_with_special_characters_in_path
    special_dir = File.join(@temp_dir, 'special-chars-dir')
    FileUtils.mkdir_p(special_dir)
    note_path = File.join(special_dir, 'note-with-special-chars.md')
    content = <<~EOF
      ---
      id: special-path
      type: general
      ---
      # Content
    EOF
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT path FROM notes WHERE id = ?', ['special-path'])
    assert_equal 1, result.length
    assert_includes result[0][0], 'special-chars-dir'
    db.close
  end

  def test_index_note_with_unicode_in_path
    unicode_dir = File.join(@temp_dir, '日本語')
    FileUtils.mkdir_p(unicode_dir)
    note_path = File.join(unicode_dir, 'ノート.md')
    content = <<~EOF
      ---
      id: unicode-path
      type: general
      ---
      # Content
    EOF
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT path FROM notes WHERE id = ?', ['unicode-path'])
    assert_equal 1, result.length
    # Path should be stored as relative path
    assert result[0][0].include?('日本語') || result[0][0].include?('ノート')
    db.close
  end

  def test_index_note_with_unicode_in_content
    content = <<~EOF
      ---
      id: unicode-content
      type: general
      title: 日本語タイトル
      ---
      # コンテンツ
      Emoji: 🎉 📝 ✨
    EOF
    note_path = File.join(@temp_dir, 'unicode-content.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT title, body FROM notes WHERE id = ?', ['unicode-content'])
    assert_equal 1, result.length
    assert_equal '日本語タイトル', result[0][0]
    assert_includes result[0][1], 'コンテンツ'
    assert_includes result[0][1], '🎉'
    db.close
  end

  def test_index_note_with_empty_metadata
    content = <<~EOF
      ---
      id: empty-metadata
      ---
      # Content
    EOF
    note_path = File.join(@temp_dir, 'empty-metadata.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT metadata FROM notes WHERE id = ?', ['empty-metadata'])
    assert_equal 1, result.length
    metadata = JSON.parse(result[0][0])
    assert_equal({ 'id' => 'empty-metadata' }, metadata)
    db.close
  end

  def test_index_note_with_special_json_characters_in_metadata
    content = <<~EOF
      ---
      id: json-special
      description: "Contains quotes and apostrophes"
      ---
      # Content
    EOF
    note_path = File.join(@temp_dir, 'json-special.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT metadata FROM notes WHERE id = ?', ['json-special'])
    assert_equal 1, result.length
    metadata = JSON.parse(result[0][0])
    assert_includes metadata['description'], 'quotes'
    assert_includes metadata['description'], 'apostrophes'
    db.close
  end

  def test_index_note_with_complex_metadata_structure
    content = <<~EOF
      ---
      id: complex-metadata
      tags:
        - tag1
        - tag2
      author:
        name: John
        email: john@example.com
      ---
      # Content
    EOF
    note_path = File.join(@temp_dir, 'complex-metadata.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT metadata FROM notes WHERE id = ?', ['complex-metadata'])
    assert_equal 1, result.length
    metadata = JSON.parse(result[0][0])
    assert_equal ['tag1', 'tag2'], metadata['tags']
    assert_equal 'John', metadata['author']['name']
    db.close
  end

  def test_index_note_relative_path_calculation
    subdir = File.join(@temp_dir, 'subdir')
    FileUtils.mkdir_p(subdir)
    note_path = File.join(subdir, 'nested-note.md')
    content = <<~EOF
      ---
      id: nested
      type: general
      ---
      # Content
    EOF
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT path FROM notes WHERE id = ?', ['nested'])
    assert_equal 1, result.length
    # Path should be relative to notebook_path
    assert_equal 'subdir/nested-note.md', result[0][0]
    db.close
  end

  def test_index_note_filename_extraction
    note_path = File.join(@temp_dir, 'deep', 'nested', 'path', 'filename.md')
    FileUtils.mkdir_p(File.dirname(note_path))
    content = <<~EOF
      ---
      id: filename-test
      type: general
      ---
      # Content
    EOF
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT filename FROM notes WHERE id = ?', ['filename-test'])
    assert_equal 1, result.length
    assert_equal 'filename.md', result[0][0]
    db.close
  end

  def test_index_note_creates_database_directory
    # Test that .zh directory is created if it doesn't exist
    new_temp_dir = Dir.mktmpdir
    config = { 'notebook_path' => new_temp_dir }
    indexer = Indexer.new(config)
    db_path = File.join(new_temp_dir, '.zh', 'index.db')
    assert File.exist?(File.dirname(db_path)), '.zh directory should be created'
    
    note_path = File.join(new_temp_dir, 'test.md')
    File.write(note_path, "---\nid: test\n---\n# Test")
    note = Note.new(path: note_path)
    indexer.index_note(note)
    assert File.exist?(db_path), 'Database should be created'
    
    FileUtils.rm_rf(new_temp_dir)
  end

  def test_index_note_handles_path_with_spaces
    spaced_dir = File.join(@temp_dir, 'path with spaces')
    FileUtils.mkdir_p(spaced_dir)
    note_path = File.join(spaced_dir, 'note with spaces.md')
    content = <<~EOF
      ---
      id: spaced-path
      type: general
      ---
      # Content
    EOF
    File.write(note_path, content)
    note = Note.new(path: note_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT path, filename FROM notes WHERE id = ?', ['spaced-path'])
    assert_equal 1, result.length
    assert_includes result[0][0], 'spaces'
    assert_equal 'note with spaces.md', result[0][1]
    db.close
  end

  def test_index_note_with_nested_subdirectories
    deep_path = File.join(@temp_dir, 'level1', 'level2', 'level3', 'deep-note.md')
    FileUtils.mkdir_p(File.dirname(deep_path))
    content = <<~EOF
      ---
      id: deep-note
      type: general
      ---
      # Content
    EOF
    File.write(deep_path, content)
    note = Note.new(path: deep_path)
    @indexer.index_note(note)
    db = SQLite3::Database.new(@db_path)
    result = db.execute('SELECT path FROM notes WHERE id = ?', ['deep-note'])
    assert_equal 1, result.length
    assert_equal 'level1/level2/level3/deep-note.md', result[0][0]
    db.close
  end

  def test_index_note_prints_debug_when_zh_debug_set
    content = <<~EOF
      ---
      id: debug-note
      type: general
      title: Debug Test
      ---
      # Content
    EOF
    note_path = File.join(@temp_dir, 'debug-note.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    saved = ENV['ZH_DEBUG']
    ENV['ZH_DEBUG'] = '1'
    stderr_capture = StringIO.new
    begin
      $stderr = stderr_capture
      @indexer.index_note(note)
    ensure
      $stderr = STDERR
      ENV['ZH_DEBUG'] = saved
    end
    output = stderr_capture.string
    assert_includes output, '[DEBUG]', 'Debug output should appear when ZH_DEBUG=1'
    assert_includes output, 'Indexing note:', 'Should log indexing start'
    assert_includes output, 'debug-note', 'Should log note path or id'
    assert_includes output, 'Insert new note: debug-note', 'Should log insert for new note'
  end

  def test_index_note_no_debug_when_zh_debug_unset
    content = <<~EOF
      ---
      id: no-debug-note
      type: general
      title: No Debug Test
      ---
      # Content
    EOF
    note_path = File.join(@temp_dir, 'no-debug-note.md')
    File.write(note_path, content)
    note = Note.new(path: note_path)
    saved = ENV['ZH_DEBUG']
    ENV.delete('ZH_DEBUG')
    stderr_capture = StringIO.new
    begin
      $stderr = stderr_capture
      @indexer.index_note(note)
    ensure
      $stderr = STDERR
      ENV['ZH_DEBUG'] = saved if saved
    end
    output = stderr_capture.string
    refute_includes output, '[DEBUG]', 'No debug output when ZH_DEBUG is unset'
  end

  def test_index_note_populates_links_table
    note_a = <<~EOF
      ---
      id: aaaa1111
      title: Note A
      ---
      # Note A
      See [[bbbb2222]].
    EOF
    note_b = <<~EOF
      ---
      id: bbbb2222
      title: Note B
      ---
      # Note B
    EOF
    path_a = File.join(@temp_dir, 'aaaa1111-a.md')
    path_b = File.join(@temp_dir, 'bbbb2222-b.md')
    File.write(path_a, note_a)
    File.write(path_b, note_b)
    @indexer.index_note(Note.new(path: path_b))
    @indexer.index_note(Note.new(path: path_a))
    db = SQLite3::Database.new(@db_path)
    links = db.execute('SELECT source_id, target_id, link_type FROM links WHERE source_id = ?', ['aaaa1111'])
    db.close
    assert_equal 1, links.size, 'Should have one link from note A to B'
    assert_equal ['aaaa1111', 'bbbb2222', 'wikilink'], links[0]

    # Backlinks section in target note file is markdown-style [title](notebook_relative_path)
    note_b_content = File.read(path_b)
    assert_includes note_b_content, '## Backlinks', 'Target note should have Backlinks section'
    assert_match %r{- \[Note A\]\(aaaa1111-a\.md\)}, note_b_content, 'Backlinks should be markdown link with title and path'
  end

  def test_backlinks_section_uses_markdown_links_and_title_fallback
    # Linking note has empty title; backlinks in target should use path basename as link text.
    note_linker = <<~EOF
      ---
      id: cccc3333
      title: ""
      ---
      # Linker
      See [[dddd4444]].
    EOF
    note_tgt = <<~EOF
      ---
      id: dddd4444
      title: Target
      ---
      # Target
    EOF
    path_linker = File.join(@temp_dir, 'cccc3333-linker.md')
    path_tgt = File.join(@temp_dir, 'dddd4444-target.md')
    File.write(path_linker, note_linker)
    File.write(path_tgt, note_tgt)
    @indexer.index_note(Note.new(path: path_tgt))
    @indexer.index_note(Note.new(path: path_linker))
    content_tgt = File.read(path_tgt)
    assert_includes content_tgt, '## Backlinks'
    assert_match %r{- \[cccc3333-linker\]\(cccc3333-linker\.md\)}, content_tgt,
                 'Backlinks should use path basename when linking note has empty title'
  end
end
