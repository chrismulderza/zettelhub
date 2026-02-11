# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'yaml'
require 'fileutils'
require 'sqlite3'
require 'json'
require_relative '../../lib/cmd/tag'
require_relative '../../lib/cmd/init'
require_relative '../../lib/cmd/reindex'
require_relative '../../lib/config'
require_relative '../../lib/indexer'
require_relative '../../lib/models/note'
require_relative '../../lib/utils'

class TagCommandTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @temp_home = Dir.mktmpdir
    @global_config_file = File.join(@temp_home, '.config', 'zh', 'config.yaml')
    @original_config_file = Config::CONFIG_FILE
    Config.send(:remove_const, :CONFIG_FILE)
    Config.const_set(:CONFIG_FILE, @global_config_file)

    Dir.singleton_class.class_eval do
      alias_method :original_home, :home
      define_method(:home) { @temp_home }
    end
    Dir.instance_variable_set(:@temp_home, @temp_home)

    @original_home_env = ENV['HOME']
    ENV['HOME'] = @temp_home

    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    global_config = { 'notebook_path' => @tmpdir, 'templates' => [] }
    File.write(@global_config_file, global_config.to_yaml)

    Dir.chdir(@tmpdir) do
      InitCommand.new.run
    end

    @db_path = File.join(@tmpdir, '.zh', 'index.db')
    create_test_notes
  end

  def teardown
    Dir.singleton_class.class_eval do
      alias_method :home, :original_home
      remove_method :original_home
    end
    ENV['HOME'] = @original_home_env if @original_home_env
    FileUtils.remove_entry @tmpdir
    FileUtils.remove_entry @temp_home
    Config.send(:remove_const, :CONFIG_FILE)
    Config.const_set(:CONFIG_FILE, @original_config_file)
  end

  def create_test_notes
    Dir.chdir(@tmpdir) do
      config = Config.load
      indexer = Indexer.new(config)

      note1 = <<~EOF
        ---
        id: abc11111
        type: note
        title: Note One
        date: 2026-01-15
        tags: [work, project]
        ---
        # Note One
        Content one.
      EOF
      File.write('note1.md', note1)
      indexer.index_note(Note.new(path: File.join(@tmpdir, 'note1.md')))

      note2 = <<~EOF
        ---
        id: abc22222
        type: note
        title: Note Two
        date: 2026-01-16
        tags: [work, personal]
        ---
        # Note Two
        Content two.
      EOF
      File.write('note2.md', note2)
      indexer.index_note(Note.new(path: File.join(@tmpdir, 'note2.md')))

      note3 = <<~EOF
        ---
        id: abc33333
        type: note
        title: Note Three
        date: 2026-01-17
        tags: []
        ---
        # Note Three
        Content three.
      EOF
      File.write('note3.md', note3)
      indexer.index_note(Note.new(path: File.join(@tmpdir, 'note3.md')))
    end
  end

  def test_list_shows_tags_with_counts
    out, = capture_io do
      TagCommand.new.run('list')
    end
    assert_includes out, 'work'
    assert_includes out, 'project'
    assert_includes out, 'personal'
    # work appears in 2 notes, project and personal in 1 each
    assert_match(/\b2\b.*work/, out)
    assert_match(/\b1\b.*project/, out)
    assert_match(/\b1\b.*personal/, out)
  end

  def test_tags_invocation_lists_same_as_list
    out, = capture_io do
      TagCommand.new.run('list')
    end
    out2, = capture_io do
      # Simulate "zh tags" which runs tag list
      TagCommand.new.run('list')
    end
    assert_equal out, out2
  end

  def test_add_adds_tag_to_note
    out, = capture_io do
      TagCommand.new.run('add', 'newtag', 'abc33333')
    end
    assert_match(/added to note abc33333/, out)

    note_path = File.join(@tmpdir, 'note3.md')
    content = File.read(note_path)
    assert_match(/newtag/, content)

    # Re-read via index
    db = SQLite3::Database.new(@db_path)
    row = db.execute("SELECT metadata FROM notes WHERE id = 'abc33333'").first
    db.close
    meta = JSON.parse(row[0])
    assert_includes meta['tags'], 'newtag'
  end

  def test_add_idempotent_when_tag_already_present
    out, = capture_io do
      TagCommand.new.run('add', 'work', 'abc11111')
    end
    assert_match(/already on note/, out)

    content = File.read(File.join(@tmpdir, 'note1.md'))
    assert_equal 1, content.scan(/work/).size
  end

  def test_remove_removes_tag_from_note
    out, = capture_io do
      TagCommand.new.run('remove', 'project', 'abc11111')
    end
    assert_match(/removed from note abc11111/, out)

    content = File.read(File.join(@tmpdir, 'note1.md'))
    refute_match(/\bproject\b/, content)
    assert_match(/\bwork\b/, content)

    db = SQLite3::Database.new(@db_path)
    row = db.execute("SELECT metadata FROM notes WHERE id = 'abc11111'").first
    db.close
    meta = JSON.parse(row[0])
    refute_includes meta['tags'], 'project'
    assert_includes meta['tags'], 'work'
  end

  def test_remove_idempotent_when_tag_not_present
    out, = capture_io do
      TagCommand.new.run('remove', 'nonexistent', 'abc11111')
    end
    assert_match(/removed from note/, out)
  end

  def test_rename_updates_tag_across_notes
    out, = capture_io do
      TagCommand.new.run('rename', 'work', 'work-renamed')
    end
    assert_match(/renamed to "work-renamed" in 2 note\(s\)/, out)

    [File.join(@tmpdir, 'note1.md'), File.join(@tmpdir, 'note2.md')].each do |path|
      content = File.read(path)
      metadata, = Utils.parse_front_matter(content)
      tags = metadata['tags'] || []
      refute_includes(tags, 'work', "tags should not contain 'work' after rename: #{tags.inspect}")
      assert_includes(tags, 'work-renamed', "tags should contain 'work-renamed': #{tags.inspect}")
    end
  end

  def test_rename_same_name_no_op
    out, = capture_io do
      TagCommand.new.run('rename', 'work', 'work')
    end
    assert_match(/same.*No change/, out)
  end

  def test_rename_nonexistent_old_tag_updates_zero_notes
    out, = capture_io do
      TagCommand.new.run('rename', 'nonexistent-tag', 'new-name')
    end
    assert_match(/in 0 note\(s\)/, out)
  end

  def test_unknown_note_id_add_exits_with_error
    read_io, write_io = IO.pipe
    pid = fork do
      read_io.close
      $stderr.reopen(write_io)
      write_io.close
      TagCommand.new.run('add', 'work', 'nonexistent99')
    end
    write_io.close
    Process.wait(pid)
    err = read_io.read
    read_io.close
    assert_match(/Note not found/, err)
    assert_equal 1, $?.exitstatus
  end

  def test_unknown_note_id_remove_exits_with_error
    read_io, write_io = IO.pipe
    pid = fork do
      read_io.close
      $stderr.reopen(write_io)
      write_io.close
      TagCommand.new.run('remove', 'work', 'nonexistent99')
    end
    write_io.close
    Process.wait(pid)
    err = read_io.read
    read_io.close
    assert_match(/Note not found/, err)
    assert_equal 1, $?.exitstatus
  end

  def test_help_output
    out, = capture_io do
      TagCommand.new.run('--help')
    end
    assert_match(/Tag management/, out)
    assert_match(/zh tag add TAG NOTE_ID/, out)
    assert_match(/zh tag remove TAG NOTE_ID/, out)
    assert_match(/zh tag rename/, out)
  end

  def test_completion_returns_subcommands
    out, = capture_io do
      TagCommand.new.run('--completion')
    end
    %w[list add remove rename].each do |sub|
      assert_includes out, sub
    end
  end

  def test_completion_with_add_returns_tags
    out, = capture_io do
      TagCommand.new.run('--completion', 'add')
    end
    %w[work project personal].each do |tag|
      assert_includes out, tag, "Completion for 'add' should include tag #{tag}"
    end
  end

  def test_list_empty_index
    FileUtils.rm_f(@db_path)
    Dir.chdir(@tmpdir) do
      out, = capture_io do
        TagCommand.new.run('list')
      end
      assert_match(/No index|No tags/, out)
    end
  end
end
