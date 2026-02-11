# frozen_string_literal: true

require 'minitest/autorun'
require 'date'
require 'fileutils'
require 'yaml'
require_relative '../../lib/cmd/init'
require_relative '../../lib/cmd/journal'
require_relative '../../lib/config'
require_relative '../../lib/utils'

class JournalCommandTest < Minitest::Test
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
    @original_home_env = ENV['HOME']
    ENV['HOME'] = @temp_home

    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    global_config = { 'notebook_path' => @tmpdir, 'templates' => [] }
    File.write(@global_config_file, global_config.to_yaml)

    Dir.chdir(@tmpdir) do
      InitCommand.new.run
      config = YAML.load_file('.zh/config.yaml')
      config['journal'] = { 'path_pattern' => 'journal/{date}.md' }
      File.write('.zh/config.yaml', config.to_yaml)
      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      journal_erb = <<~ERB
        ---
        id: "<%= id %>"
        type: journal
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        description: >
          <%= description.to_s.gsub("\\n", "\\n  ") %>
        config:
          path: "journal/<%= date %>.md"
          default_tags:
            - journal
            - daily
        ---
        # Journal for <%= title %>
        Content
      ERB
      File.write(File.join(template_dir, 'journal.erb'), journal_erb)
    end
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

  def test_completion_returns_today_yesterday
    Dir.chdir(@tmpdir) do
      out, _err = capture_io do
        JournalCommand.new.run('--completion')
      end
      assert_includes out, 'today'
      assert_includes out, 'yesterday'
    end
  end

  def test_resolve_date_today_creates_path_with_today
    Dir.chdir(@tmpdir) do
      today_str = Date.today.strftime('%Y-%m-%d')
      expected_path = File.join(@tmpdir, 'journal', "#{today_str}.md")
      system_called = false
      system_cmd = nil
      JournalCommand.class_eval do
        define_method(:system) do |cmd|
          system_called = true
          system_cmd = cmd
          true
        end
      end
      begin
        JournalCommand.new.run('today')
        assert system_called, 'system(editor) should be called'
        assert system_cmd&.include?(expected_path), "Editor should receive path #{expected_path}, got #{system_cmd}"
      ensure
        JournalCommand.class_eval do
          remove_method :system
        end
      end
    end
  end

  def test_journal_with_no_args_behaves_like_today
    Dir.chdir(@tmpdir) do
      today_str = Date.today.strftime('%Y-%m-%d')
      notebook = File.realpath(@tmpdir)
      expected_path = File.join(notebook, 'journal', "#{today_str}.md")
      system_cmd = nil
      JournalCommand.class_eval do
        define_method(:system) do |cmd|
          system_cmd = cmd
          true
        end
      end
      begin
        JournalCommand.new.run
        assert system_cmd&.include?(expected_path), "zh journal with no args should open today's journal at #{expected_path}, got #{system_cmd}"
      ensure
        JournalCommand.class_eval do
          remove_method :system
        end
      end
    end
  end

  def test_resolve_date_yesterday_creates_path_with_yesterday
    Dir.chdir(@tmpdir) do
      yesterday_str = (Date.today - 1).strftime('%Y-%m-%d')
      expected_path = File.join(@tmpdir, 'journal', "#{yesterday_str}.md")
      system_called = false
      system_cmd = nil
      JournalCommand.class_eval do
        define_method(:system) do |cmd|
          system_called = true
          system_cmd = cmd
          true
        end
      end
      begin
        JournalCommand.new.run('yesterday')
        assert system_called
        assert system_cmd&.include?(expected_path), "Editor should receive #{expected_path}, got #{system_cmd}"
      ensure
        JournalCommand.class_eval do
          remove_method :system
        end
      end
    end
  end

  def test_resolve_date_parses_date_string
    Dir.chdir(@tmpdir) do
      expected_path = File.join(@tmpdir, 'journal', '2025-02-05.md')
      system_cmd = nil
      JournalCommand.class_eval do
        define_method(:system) do |cmd|
          system_cmd = cmd
          true
        end
      end
      begin
        JournalCommand.new.run('2025-02-05')
        assert system_cmd&.include?(expected_path), "Editor should receive #{expected_path}, got #{system_cmd}"
      ensure
        JournalCommand.class_eval do
          remove_method :system
        end
      end
    end
  end

  def test_invalid_date_exits_with_error
    Dir.chdir(@tmpdir) do
      read_io, write_io = IO.pipe
      pid = fork do
        read_io.close
        $stderr.reopen(write_io)
        write_io.close
        JournalCommand.new.run('not-a-date')
      end
      write_io.close
      Process.wait(pid)
      err = read_io.read
      read_io.close
      assert_match(/Invalid date/i, err)
      assert_equal 1, $?.exitstatus
    end
  end

  def test_path_uses_journal_path_pattern_and_engine_date_format
    Dir.chdir(@tmpdir) do
      JournalCommand.class_eval do
        define_method(:system) { |_cmd| true }
      end
      begin
        JournalCommand.new.run('2025-02-05')
        notebook = File.realpath(@tmpdir)
        path = File.join(notebook, 'journal', '2025-02-05.md')
        assert File.exist?(path), "Default pattern should create #{path}"
      ensure
        JournalCommand.class_eval { remove_method :system }
      end
    end
  end

  def test_creates_and_indexes_when_file_missing
    Dir.chdir(@tmpdir) do
      JournalCommand.class_eval do
        define_method(:system) { |_cmd| true }
      end
      begin
        JournalCommand.new.run('2025-03-15')
        path = File.join(@tmpdir, 'journal', '2025-03-15.md')
        assert File.exist?(path), "Journal file should be created at #{path}"
        content = File.read(path)
        assert_includes content, '2025-03-15'
        assert_includes content, 'Journal for 2025-03-15'
        db_path = Config.index_db_path(Config.load['notebook_path'])
        assert File.exist?(db_path)
        require 'sqlite3'
        db = SQLite3::Database.new(db_path)
        rows = db.execute("SELECT path FROM notes WHERE path LIKE '%2025-03-15%'")
        db.close
        assert_equal 1, rows.size, 'New journal should be indexed'
        metadata, = Utils.parse_front_matter(content)
        assert_equal %w[journal daily], metadata['tags'], 'Journal file should have default_tags from template config'
        refute metadata.key?('config'), 'config block should be removed from output'
      ensure
        JournalCommand.class_eval { remove_method :system }
      end
    end
  end

  def test_opens_existing_file_without_creating
    Dir.chdir(@tmpdir) do
      journal_dir = File.join(@tmpdir, 'journal')
      FileUtils.mkdir_p(journal_dir)
      existing = File.join(journal_dir, '2025-04-20.md')
      File.write(existing, "---\ndate: 2025-04-20\n---\n# Existing\n")
      system_cmd = nil
      JournalCommand.class_eval do
        define_method(:system) do |cmd|
          system_cmd = cmd
          true
        end
      end
      begin
        JournalCommand.new.run('2025-04-20')
        assert system_cmd&.include?(existing), "Editor should open existing file: #{system_cmd}"
        assert_equal "---\ndate: 2025-04-20\n---\n# Existing\n", File.read(existing), 'Content should be unchanged'
      ensure
        JournalCommand.class_eval { remove_method :system }
      end
    end
  end

  def test_does_not_overwrite_existing_when_template_path_differs_from_config
    # Template uses journal/<%= year %>/<%= date %>.md; config uses journal/{date}.md.
    # Pre-create file at template path; journal must not overwrite it.
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['journal'] = { 'path_pattern' => 'journal/{date}.md' }
      File.write('.zh/config.yaml', config.to_yaml)
      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      journal_erb_by_year = <<~ERB
        ---
        id: "<%= id %>"
        type: journal
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        description: >
          <%= description.to_s.gsub("\\n", "\\n  ") %>
        config:
          path: "journal/<%= year %>/<%= date %>.md"
          default_tags:
            - journal
            - daily
        ---
        # Journal for <%= title %>
        Content
      ERB
      File.write(File.join(template_dir, 'journal.erb'), journal_erb_by_year)

      journal_2025_dir = File.join(@tmpdir, 'journal', '2025')
      FileUtils.mkdir_p(journal_2025_dir)
      existing = File.join(journal_2025_dir, '2025-04-20.md')
      existing_content = "---\ndate: 2025-04-20\n---\n# Existing by year\n"
      File.write(existing, existing_content)

      system_cmd = nil
      JournalCommand.class_eval do
        define_method(:system) do |cmd|
          system_cmd = cmd
          true
        end
      end
      begin
        JournalCommand.new.run('2025-04-20')
        assert system_cmd&.include?(existing), "Editor should open existing file at template path: #{system_cmd}"
        assert_equal existing_content, File.read(existing), 'Content should be unchanged (no overwrite)'
      ensure
        JournalCommand.class_eval { remove_method :system }
      end
    end
  end

  def test_help_output
    Dir.chdir(@tmpdir) do
      out, _err = capture_io do
        JournalCommand.new.run('--help')
      end
      assert_includes out, 'today'
      assert_includes out, 'yesterday'
      assert_includes out, 'journal'
    end
  end

  def test_uses_configurable_default_title
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['journal'] ||= {}
      config['journal']['default_title'] = 'Daily: {date}'
      File.write('.zh/config.yaml', config.to_yaml)

      JournalCommand.class_eval do
        define_method(:system) { |_cmd| true }
      end
      begin
        JournalCommand.new.run('2025-03-15')
        path = File.join(@tmpdir, 'journal', '2025-03-15.md')
        assert File.exist?(path), "Journal file should be created at #{path}"
        content = File.read(path)
        assert_includes content, 'Daily: 2025-03-15', 'Title should use configured default_title pattern'
      ensure
        JournalCommand.class_eval { remove_method :system }
      end
    end
  end
end
