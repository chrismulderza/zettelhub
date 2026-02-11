# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'json'
require 'sqlite3'
require_relative '../test_helper' if File.exist?(File.join(__dir__, 'test_helper.rb'))
require_relative '../../lib/config'
require_relative '../../lib/indexer'
require_relative '../../lib/models/note'
require_relative '../../lib/cmd/bookmark'

class BookmarkCommandTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @notebook = @tmpdir
    FileUtils.mkdir_p(File.join(@notebook, '.zh'))
    File.write(File.join(@notebook, '.zh', 'config.yaml'), "notebook_path: #{@notebook}\n")
    @saved_notebook_path = ENV['ZH_NOTEBOOK_PATH']
    ENV['ZH_NOTEBOOK_PATH'] = @notebook
    @config = Config.load(debug: false)
    @config['notebook_path'] = @notebook
    @indexer = Indexer.new(@config)
    # Stub system so add subcommand does not open editor
    BookmarkCommand.class_eval do
      define_method(:system) { |*_args| true }
    end
  end

  def teardown
    ENV['ZH_NOTEBOOK_PATH'] = @saved_notebook_path if defined?(@saved_notebook_path)
    BookmarkCommand.class_eval { remove_method :system } if BookmarkCommand.method_defined?(:system)
    FileUtils.rm_rf(@tmpdir)
  end

  def test_help
    Dir.chdir(@notebook) do
      out, err = capture_io do
        BookmarkCommand.new.run('--help')
      end
      assert_equal '', err
      assert_includes out, 'Bookmark management'
      assert_includes out, 'zh bookmark add'
      assert_includes out, 'zh bookmark export'
      assert_includes out, 'zh bookmark refresh'
    end
  end

  def test_completion
    Dir.chdir(@notebook) do
      out, err = capture_io do
        BookmarkCommand.new.run('--completion')
      end
      assert_equal '', err
      assert_includes out, 'add'
      assert_includes out, 'export'
      assert_includes out, 'refresh'
    end
  end

  def test_refresh_help
    Dir.chdir(@notebook) do
      out, err = capture_io do
        BookmarkCommand.new.run('refresh', '--help')
      end
      assert_equal '', err
      assert_includes out, 'refresh'
      assert_includes out, 'validate'
      assert_includes out, 'stale'
    end
  end

  def test_refresh_marks_unreachable_as_stale
    # Create bookmark file and index it
    bookmark_path = File.join(@notebook, 'bookmarks', 'stale-test.md')
    FileUtils.mkdir_p(File.dirname(bookmark_path))
    content = <<~MD
      ---
      id: stale1234
      type: bookmark
      uri: "https://example.com/gone"
      title: "Gone Page"
      tags: [web]
      description: ""
      ---
      # Gone Page
    MD
    File.write(bookmark_path, content)
    @indexer.index_note(Note.new(path: bookmark_path))

    # Stub uri_reachable? to return false so refresh marks as stale
    BookmarkCommand.class_eval do
      alias_method :old_uri_reachable?, :uri_reachable?
      define_method(:uri_reachable?) { |_uri_str| false }
    end

    Dir.chdir(@notebook) do
      out, err = capture_io do
        BookmarkCommand.new.run('refresh')
      end
      assert_equal '', err
      assert_includes out, 'marked stale'
    end

    content_after = File.read(bookmark_path)
    assert_includes content_after, 'stale', 'tags should include stale'
    assert_match(/title:.*Stale-/m, content_after, 'title should be prefixed with Stale-')
  ensure
    BookmarkCommand.class_eval do
      define_method(:uri_reachable?) { |uri_str| old_uri_reachable?(uri_str) }
      remove_method :old_uri_reachable?
    end
  end

  def test_refresh_fetches_description_when_empty
    bookmark_path = File.join(@notebook, 'bookmarks', 'desc-fetch.md')
    FileUtils.mkdir_p(File.dirname(bookmark_path))
    content = <<~MD
      ---
      id: desc5678
      type: bookmark
      uri: "https://example.com/page"
      title: "No Description"
      tags: []
      description: ""
      ---
      # No Description
    MD
    File.write(bookmark_path, content)
    @indexer.index_note(Note.new(path: bookmark_path))

    # Stub uri_reachable? true and fetch_meta_description to return a string
    BookmarkCommand.class_eval do
      alias_method :old_uri_reachable_refresh_desc, :uri_reachable?
      alias_method :old_fetch_meta_description, :fetch_meta_description
      define_method(:uri_reachable?) { |_uri_str| true }
      define_method(:fetch_meta_description) { |_uri_str| 'Fetched description from page' }
    end

    Dir.chdir(@notebook) do
      out, err = capture_io do
        BookmarkCommand.new.run('refresh')
      end
      assert_equal '', err
      assert_includes out, 'description(s) updated'
    end

    content_after = File.read(bookmark_path)
    assert_includes content_after, 'Fetched description from page', 'description should be filled'
  ensure
    # Restore original methods (keep old_* names so restored methods can delegate)
    BookmarkCommand.class_eval do
      define_method(:uri_reachable?) { |uri_str| old_uri_reachable_refresh_desc(uri_str) }
      define_method(:fetch_meta_description) { |uri_str| old_fetch_meta_description(uri_str) }
    end
  end

  def test_refresh_skips_non_http_uris
    bookmark_path = File.join(@notebook, 'bookmarks', 'file-uri.md')
    FileUtils.mkdir_p(File.dirname(bookmark_path))
    content = <<~MD
      ---
      id: file9999
      type: bookmark
      uri: "file:///local/path"
      title: "Local Bookmark"
      tags: [local]
      description: ""
      ---
      # Local
    MD
    File.write(bookmark_path, content)
    @indexer.index_note(Note.new(path: bookmark_path))

    Dir.chdir(@notebook) do
      out, err = capture_io do
        BookmarkCommand.new.run('refresh')
      end
      assert_equal '', err
    end

    content_after = File.read(bookmark_path)
    assert_includes content_after, 'Local Bookmark', 'title unchanged'
    refute_includes content_after, 'stale', 'file:// URIs should not get stale tag'
  end

  def test_add_creates_file_and_indexes
    Dir.chdir(@notebook) do
      out, err = capture_io do
        BookmarkCommand.new.run('add', 'https://example.com/bookmark', '--title', 'Example Bookmark', '--tags', 'web,ref', '--description', '')
      end
      assert_equal '', err
      assert_includes out, 'Bookmark created:'
      assert_match(%r{bookmarks/.*\.md}, out)

      # File should exist under notebook with uri in front matter (path from template: resources/bookmarks/ or bookmarks/)
      files = Dir[File.join(@notebook, '**/*.md')]
      assert files.any?, "Expected a bookmark file, got #{files}"
      content = File.read(files.first)
      assert_includes content, 'type: bookmark'
      assert_includes content, 'https://example.com/bookmark'
      assert_includes content, 'Example Bookmark'
      # Alias should be from template default_alias (e.g. "bookmark> {title}")
      assert_includes content, 'bookmark> Example Bookmark', 'aliases should use template default_alias'

      # Index should contain the bookmark
      db_path = Config.index_db_path(@notebook)
      assert File.exist?(db_path)
      db = SQLite3::Database.new(db_path)
      row = db.execute("SELECT id, metadata FROM notes WHERE json_extract(metadata, '$.type') = 'bookmark'").first
      db.close
      assert row, 'Bookmark should be in index'
      meta = JSON.parse(row[1])
      assert_equal 'https://example.com/bookmark', meta['uri']
    end
  end

  def test_export_produces_html
    # Create index with one bookmark (notes table only; export does not use FTS)
    db_path = Config.index_db_path(@notebook)
    FileUtils.mkdir_p(File.dirname(db_path))
    db = SQLite3::Database.new(db_path)
    db.execute('CREATE TABLE notes (id TEXT PRIMARY KEY, path TEXT, metadata TEXT, title TEXT, body TEXT, filename TEXT)')
    db.execute(
      'INSERT INTO notes (id, path, metadata, title, body, filename) VALUES (?, ?, ?, ?, ?, ?)',
      ['abc12345', 'bookmarks/abc12345-example.md', JSON.generate({ 'type' => 'bookmark', 'uri' => 'https://example.com', 'title' => 'Example' }), 'Example', '', 'abc12345-example.md']
    )
    db.close

    out_path = File.join(@notebook, 'exported.html')
    Dir.chdir(@notebook) do
      out, err = capture_io do
        BookmarkCommand.new.run('export', '--output', out_path)
      end
      assert_equal '', err
      assert_includes out, 'Exported 1 bookmark'
    end
    html = File.read(out_path)
    assert_includes html, 'NETSCAPE-Bookmark-file-1'
    assert_includes html, 'https://example.com'
    assert_includes html, 'Example'
  end

  def test_browser_no_bookmarks_prints_message
    # Empty index (no notes table yet) - reindex would create it. Create minimal schema so query runs.
    db_path = Config.index_db_path(@notebook)
    FileUtils.mkdir_p(File.dirname(db_path))
    db = SQLite3::Database.new(db_path)
    db.execute('CREATE TABLE IF NOT EXISTS notes (id TEXT PRIMARY KEY, path TEXT, metadata TEXT, title TEXT, body TEXT, filename TEXT)')
    db.execute("CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(id, full_text)")
    db.close

    Dir.chdir(@notebook) do
      # Stub IO.popen so fzf is not actually run; we only care about "No bookmarks" when list is empty
      out, err = capture_io do
        BookmarkCommand.new.run
      end
      assert_includes out, 'No bookmarks found'
    end
  end
end
