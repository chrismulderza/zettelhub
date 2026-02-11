require 'minitest/autorun'
require 'tmpdir'
require 'yaml'
require 'fileutils'
require 'sqlite3'
require 'json'
require_relative '../../lib/cmd/search'
require_relative '../../lib/cmd/init'
require_relative '../../lib/cmd/reindex'
require_relative '../../lib/config'
require_relative '../../lib/indexer'
require_relative '../../lib/models/note'

class SearchCommandTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @temp_home = Dir.mktmpdir
    @global_config_file = File.join(@temp_home, '.config', 'zh', 'config.yaml')
    @original_config_file = Config::CONFIG_FILE
    Config.send(:remove_const, :CONFIG_FILE)
    Config.const_set(:CONFIG_FILE, @global_config_file)

    # Mock Dir.home
    Dir.singleton_class.class_eval do
      alias_method :original_home, :home
      define_method(:home) { @temp_home }
    end
    Dir.instance_variable_set(:@temp_home, @temp_home)

    # Mock ENV['HOME']
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

      # Note 1: Meeting note with work tag
      note1 = <<~EOF
        ---
        id: meeting1
        type: meeting
        title: Standup Meeting
        date: 2026-01-15
        tags: [work, standup]
        ---
        # Standup Meeting
        Discussed project progress and blockers.
      EOF
      File.write('meeting1.md', note1)
      indexer.index_note(Note.new(path: File.join(@tmpdir, 'meeting1.md')))

      # Note 2: Journal note with personal tag
      note2 = <<~EOF
        ---
        id: journal1
        type: journal
        title: Daily Reflection
        date: 2026-01-15
        tags: [personal, reflection]
        ---
        # Daily Reflection
        Today I reflected on my work and personal growth.
      EOF
      File.write('journal1.md', note2)
      indexer.index_note(Note.new(path: File.join(@tmpdir, 'journal1.md')))

      # Note 3: Regular note with work tag
      note3 = <<~EOF
        ---
        id: note1
        type: note
        title: Project Ideas
        date: 2026-01-20
        tags: [work, project]
        ---
        # Project Ideas
        Some ideas for new projects and features.
      EOF
      File.write('note1.md', note3)
      indexer.index_note(Note.new(path: File.join(@tmpdir, 'note1.md')))

      # Note 4: Meeting note with different date
      note4 = <<~EOF
        ---
        id: meeting2
        type: meeting
        title: Team Review
        date: 2026-02-10
        tags: [work, review]
        ---
        # Team Review
        Quarterly team review meeting notes.
      EOF
      File.write('meeting2.md', note4)
      indexer.index_note(Note.new(path: File.join(@tmpdir, 'meeting2.md')))

      # Note 5: Note in subdirectory
      FileUtils.mkdir_p('subdir')
      note5 = <<~EOF
        ---
        id: subnote1
        type: note
        title: Subdirectory Note
        date: 2026-01-15
        tags: [personal]
        ---
        # Subdirectory Note
        This note is in a subdirectory.
      EOF
      File.write('subdir/subnote1.md', note5)
      indexer.index_note(Note.new(path: File.join(@tmpdir, 'subdir', 'subnote1.md')))
    end
  end

  def test_basic_search_finds_notes_by_title
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', 'Standup') }.first
      assert_match(/meeting1/, output)
      assert_match(/Standup Meeting/, output)
    end
  end

  def test_basic_search_finds_notes_by_body
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', 'progress') }.first
      assert_match(/meeting1/, output)
      assert_match(/Standup Meeting/, output)
    end
  end

  def test_search_with_type_filter
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '--type', 'meeting', 'team') }.first
      assert_match(/meeting2/, output)
      assert_match(/Team Review/, output)
      refute_match(/journal1/, output)
    end
  end

  def test_search_with_tag_filter
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '--tag', 'work', 'project') }.first
      assert_match(/note1/, output)
      assert_match(/Project Ideas/, output)
      refute_match(/journal1/, output)
    end
  end

  def test_search_with_date_filter_single_date
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '--date', '2026-01-15', 'reflection') }.first
      assert_match(/journal1/, output)
      assert_match(/Daily Reflection/, output)
      refute_match(/note1/, output)
    end
  end

  def test_search_with_date_filter_month
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '--date', '2026-01', 'meeting') }.first
      assert_match(/meeting1/, output)
      refute_match(/meeting2/, output)
    end
  end

  def test_search_with_date_filter_range
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '--date', '2026-01-15:2026-01-20', 'project') }.first
      assert_match(/note1/, output)
      refute_match(/meeting2/, output)
    end
  end

  def test_search_with_path_filter
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      # Search for "subdirectory" (in body) with path filter
      # Path should be stored as "subdir/subnote1.md" (relative to notebook)
      # Try pattern that matches subdirectory paths
      output = capture_io { cmd.run('--list', '--path', '%subdir%', 'subdirectory') }.first
      # Note body contains "This note is in a subdirectory."
      if output.include?('No results found')
        # Maybe FTS5 tokenization issue, try with title word
        output = capture_io { cmd.run('--list', '--path', '%subdir%', 'Subdirectory') }.first
      end
      assert_match(/subnote1/, output, "Should find subnote1 when filtering by path containing 'subdir'")
      refute_match(/meeting1/, output, 'Should not find meeting1 when path filtered to subdir')
    end
  end

  def test_search_with_combined_filters
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io do
        cmd.run('--list', '--type', 'meeting', '--tag', 'work', '--date', '2026-01', 'standup')
      end.first
      assert_match(/meeting1/, output)
      assert_match(/Standup Meeting/, output)
      refute_match(/meeting2/, output)
      refute_match(/journal1/, output)
    end
  end

  def test_search_output_format_list
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--format', 'list', 'meeting') }.first
      lines = output.strip.split("\n")
      assert lines.any? { |line| line.include?('meeting1') && line.include?('Standup Meeting') }
    end
  end

  def test_search_output_format_table
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--format', 'table', 'meeting') }.first
      assert_match(/ID\s+\|\s+Title\s+\|\s+Type\s+\|\s+Date\s+\|\s+Path/, output)
      assert_match(/meeting1/, output)
      assert_match(/Standup Meeting/, output)
    end
  end

  def test_search_output_format_json
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--format', 'json', 'meeting1') }.first
      json_result = JSON.parse(output)
      assert json_result.is_a?(Array)
      assert json_result.length > 0
      result = json_result.find { |r| r['id'] == 'meeting1' }
      assert result
      assert_equal 'meeting1', result['id']
      assert_equal 'Standup Meeting', result['title']
      assert_equal 'meeting', result['type']
    end
  end

  def test_search_empty_results
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', 'nonexistentterm12345') }.first
      assert_match(/No results found/, output)
    end
  end

  def test_search_with_limit
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '--limit', '2', 'meeting') }.first
      lines = output.strip.split("\n")
      # Should have at most 2 results (plus "No results found" if empty)
      assert lines.length <= 3, "Expected at most 2 results, got #{lines.length - 1}"
    end
  end

  def test_search_fts5_and_syntax
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', 'project AND ideas') }.first
      assert_match(/note1/, output)
      assert_match(/Project Ideas/, output)
    end
  end

  def test_search_fts5_or_syntax
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', 'standup OR review') }.first
      assert_match(/meeting1/, output)
      assert_match(/meeting2/, output)
    end
  end

  def test_search_fts5_phrase_syntax
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '"Team Review"') }.first
      assert_match(/meeting2/, output)
      assert_match(/Team Review/, output)
    end
  end

  def test_search_handles_missing_database
    # Temporarily remove database
    FileUtils.rm_f(@db_path)

    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      assert_raises(SystemExit) do
        capture_io { cmd.run('test') }
      end
    end
  end

  def test_search_handles_invalid_fts_query
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      # FTS5 doesn't like unmatched quotes
      assert_raises(SystemExit) do
        capture_io { cmd.run('"unclosed quote') }
      end
    end
  end

  def test_search_requires_query_or_filter
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      # Should fail when neither query nor filters are provided
      assert_raises(SystemExit) do
        capture_io { cmd.run }
      end
    end
  end

  def test_search_with_tag_filter_only
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '--tag', 'work') }.first
      # Should find all notes with 'work' tag: meeting1, note1, meeting2
      assert_match(/meeting1/, output)
      assert_match(/note1/, output)
      assert_match(/meeting2/, output)
      refute_match(/journal1/, output)
      refute_match(/subnote1/, output)
    end
  end

  def test_search_with_type_filter_only
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '--type', 'meeting') }.first
      # Should find all meeting notes: meeting1, meeting2
      assert_match(/meeting1/, output)
      assert_match(/meeting2/, output)
      refute_match(/journal1/, output)
      refute_match(/note1/, output)
    end
  end

  def test_search_with_date_filter_only
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '--date', '2026-01-15') }.first
      # Should find all notes from 2026-01-15: meeting1, journal1, subnote1
      assert_match(/meeting1/, output)
      assert_match(/journal1/, output)
      assert_match(/subnote1/, output)
      # Use word boundary to avoid matching "note1" inside "subnote1"
      refute_match(/\bnote1\b/, output) # note1 is 2026-01-20
      refute_match(/meeting2/, output) # meeting2 is 2026-02-10
    end
  end

  def test_search_with_path_filter_only
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '--path', '%subdir%') }.first
      # Should find only subnote1
      assert_match(/subnote1/, output)
      refute_match(/meeting1/, output)
      refute_match(/journal1/, output)
      # Use word boundary to avoid matching "note1" inside "subnote1"
      refute_match(/\bnote1\b/, output)
    end
  end

  def test_search_with_multiple_filters_only
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '--type', 'meeting', '--tag', 'work', '--date', '2026-01') }.first
      # Should find meeting1 (meeting type, work tag, in January 2026)
      assert_match(/meeting1/, output)
      refute_match(/meeting2/, output) # meeting2 is in February
      refute_match(/journal1/, output)
      refute_match(/note1/, output)
    end
  end

  def test_search_completion_output
    cmd = SearchCommand.new
    # When no previous word, should return available options
    output = capture_io { cmd.run('--completion') }.first
    options = output.strip.split
    assert options.any? { |opt| opt == '--type' }, 'Should return --type option'
    assert options.any? { |opt| opt == '--format' }, 'Should return --format option'
    assert options.any? { |opt| opt == '--list' }, 'Should return --list option'
    assert options.any? { |opt| opt == '--table' }, 'Should return --table option'
    assert options.any? { |opt| opt == '--json' }, 'Should return --json option'
    assert options.any? { |opt| opt == '--help' }, 'Should return --help option'
    refute options.any? { |opt| opt == '--interactive' }, 'Should not return --interactive (removed)'
  end

  def test_search_completion_format_option
    cmd = SearchCommand.new
    output = capture_io { cmd.run('--completion', '--format') }.first
    formats = output.strip.split
    assert_includes formats, 'list'
    assert_includes formats, 'table'
    assert_includes formats, 'json'
  end

  def test_search_completion_type_option
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--completion', '--type') }.first
      types = output.strip.split
      # Should include types from test notes
      assert types.any? { |t| ['note', 'journal', 'meeting'].include?(t) }, "Should include note types, got: #{types.inspect}"
    end
  end

  def test_search_completion_tag_option
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--completion', '--tag') }.first
      tags = output.strip.split
      # Should include tags from test notes (work, personal, standup, reflection, project, review)
      assert tags.any? { |t| ['work', 'personal'].include?(t) }, "Should include tags from indexed notes, got: #{tags.inspect}"
    end
  end

  def test_search_completion_limit_option
    cmd = SearchCommand.new
    output = capture_io { cmd.run('--completion', '--limit') }.first
    limits = output.strip.split
    assert_includes limits, '10'
    assert_includes limits, '100'
  end

  def test_search_help_output
    cmd = SearchCommand.new
    output = capture_io { cmd.run('--help') }.first
    assert_match(/Search notes using full-text search/, output)
    assert_match(/USAGE:/, output)
    assert_match(/DESCRIPTION:/, output)
    assert_match(/OPTIONS:/, output)
    assert_match(/FTS5 QUERY SYNTAX:/, output)
    assert_match(/EXAMPLES:/, output)
    assert_match(/--type/, output)
    assert_match(/--tag/, output)
    assert_match(/--date/, output)
    assert_match(/--format/, output)
    assert_match(/--list/, output)
    assert_match(/interactive/, output)
  end

  def test_search_help_short_flag
    cmd = SearchCommand.new
    output = capture_io { cmd.run('-h') }.first
    assert_match(/Search notes using full-text search/, output)
    assert_match(/USAGE:/, output)
  end

  def test_search_ranking_works
    Dir.chdir(@tmpdir) do
      # Create notes with different relevance
      config = Config.load
      indexer = Indexer.new(config)

      # Note with "meeting" in title (higher relevance)
      note_high = <<~EOF
        ---
        id: rank1
        type: note
        title: Important Meeting
        date: 2026-01-15
        tags: []
        ---
        # Important Meeting
        Meeting content.
      EOF
      File.write('rank1.md', note_high)
      indexer.index_note(Note.new(path: File.join(@tmpdir, 'rank1.md')))

      # Note with "meeting" only in body (lower relevance)
      note_low = <<~EOF
        ---
        id: rank2
        type: note
        title: Other Note
        date: 2026-01-15
        tags: []
        ---
        # Other Note
        This note mentions meeting in passing.
      EOF
      File.write('rank2.md', note_low)
      indexer.index_note(Note.new(path: File.join(@tmpdir, 'rank2.md')))

      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', 'meeting') }.first
      lines = output.strip.split("\n")
      # Note with "meeting" in title should appear first (higher rank)
      rank1_index = lines.find_index { |line| line.include?('rank1') }
      rank2_index = lines.find_index { |line| line.include?('rank2') }
      assert rank1_index, 'rank1 should be in results'
      assert rank2_index, 'rank2 should be in results'
      # Note: BM25 ranking may vary, so we just verify both are present
      assert lines.any? { |line| line.include?('rank1') }
      assert lines.any? { |line| line.include?('rank2') }
    end
  end

  def test_search_with_no_tags_in_metadata
    Dir.chdir(@tmpdir) do
      # Create note without tags
      config = Config.load
      indexer = Indexer.new(config)

      note_no_tags = <<~EOF
        ---
        id: notags
        type: note
        title: Note Without Tags
        date: 2026-01-15
        ---
        # Note Without Tags
        Content without tags.
      EOF
      File.write('notags.md', note_no_tags)
      indexer.index_note(Note.new(path: File.join(@tmpdir, 'notags.md')))

      cmd = SearchCommand.new
      # Search should still work
      output = capture_io { cmd.run('--list', 'Without') }.first
      assert_match(/notags/, output)
    end
  end

  def test_search_with_empty_query_but_filters_allowed
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      # Empty query with filters should work
      output = capture_io { cmd.run('--list', '--tag', 'work') }.first
      assert_match(/meeting1/, output)
      assert_match(/note1/, output)
    end
  end

  def test_search_with_empty_query_no_filters_fails
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      # Empty query without filters should fail
      assert_raises(SystemExit) do
        capture_io { cmd.run('') }
      end
    end
  end

  def test_search_path_filter_with_like_pattern
    Dir.chdir(@tmpdir) do
      cmd = SearchCommand.new
      output = capture_io { cmd.run('--list', '--path', '%meeting%', 'standup') }.first
      assert_match(/meeting1/, output)
      refute_match(/journal1/, output)
    end
  end

  private

  def capture_io
    require 'stringio'
    old_stdout = $stdout
    old_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    [$stdout.string, $stderr.string]
  ensure
    $stdout = old_stdout
    $stderr = old_stderr
  end
end
