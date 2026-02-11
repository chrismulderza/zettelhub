# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'pathname'
require_relative '../test_helper' if File.exist?(File.join(__dir__, 'test_helper.rb'))
require_relative '../../lib/config'
require_relative '../../lib/indexer'
require_relative '../../lib/models/note'
require_relative '../../lib/cmd/links'

class LinksCommandTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @notebook = @tmpdir
    FileUtils.mkdir_p(File.join(@notebook, '.zh'))
    File.write(File.join(@notebook, '.zh', 'config.yaml'), "notebook_path: #{@notebook}\n")
    @saved_notebook_path = ENV['ZH_NOTEBOOK_PATH']
    ENV['ZH_NOTEBOOK_PATH'] = @notebook
    @config = Config.load_with_notebook(debug: false)
    @config['notebook_path'] = @notebook
    @indexer = Indexer.new(@config)
  end

  def teardown
    ENV['ZH_NOTEBOOK_PATH'] = @saved_notebook_path if defined?(@saved_notebook_path)
    FileUtils.rm_rf(@tmpdir)
  end

  def test_links_lists_outgoing_links
    note_a = <<~MD
      ---
      id: aaaa1111
      title: Note A
      ---
      # Note A
      See [[bbbb2222]] and [B](bbbb2222-b.md).
    MD
    note_b = <<~MD
      ---
      id: bbbb2222
      title: Note B
      ---
      # Note B
    MD
    File.write(File.join(@notebook, 'aaaa1111-note-a.md'), note_a)
    File.write(File.join(@notebook, 'bbbb2222-b.md'), note_b)
    # Index target first so link resolution finds it
    @indexer.index_note(Note.new(path: File.join(@notebook, 'bbbb2222-b.md')))
    @indexer.index_note(Note.new(path: File.join(@notebook, 'aaaa1111-note-a.md')))

    out, err = nil
    Dir.chdir(@notebook) do
      out, err = capture_io do
        LinksCommand.new.run('aaaa1111')
      end
    end
    assert_equal '', err
    assert_includes out, 'bbbb2222'
    assert_includes out, 'wikilink'
    assert_includes out, 'markdown'
  end

  def test_links_no_links
    note_a = <<~MD
      ---
      id: aaaa1111
      title: Note A
      ---
      # Note A
      No links.
    MD
    File.write(File.join(@notebook, 'aaaa1111-note-a.md'), note_a)
    @indexer.index_note(Note.new(path: File.join(@notebook, 'aaaa1111-note-a.md')))

    out, err = nil
    Dir.chdir(@notebook) do
      out, err = capture_io do
        LinksCommand.new.run('aaaa1111')
      end
    end
    assert_equal '', err
    assert_includes out, 'No outgoing links'
  end

  def test_links_requires_note_id
    err = capture_io do
      assert_raises(SystemExit) { LinksCommand.new.run }
    end
    assert err[1].include?('Usage')
  end
end
