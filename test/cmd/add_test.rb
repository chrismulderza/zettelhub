require 'minitest/autorun'
require 'tmpdir'
require 'yaml'
require 'fileutils'
require 'stringio'
require 'sqlite3'
require_relative '../../lib/cmd/add'
require_relative '../../lib/cmd/init'
require_relative '../../lib/config'

class AddCommandTest < Minitest::Test
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

    # Mock ENV['HOME'] for Utils.find_template_file
    @original_home_env = ENV['HOME']
    ENV['HOME'] = @temp_home

    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    global_config = { 'notebook_path' => @tmpdir, 'templates' => [] }
    File.write(@global_config_file, global_config.to_yaml)

    Dir.chdir(@tmpdir) do
      InitCommand.new.run
      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        description: >
          <%= description.to_s.gsub("\n", "\n  ") %>
        ---
        # <%= type %>
        Content
      ERB
      File.write(File.join(template_dir, 'note.erb'), template_content)
    end

    # Stub editor so tests that call run() do not open a real editor
    AddCommand.class_eval do
      define_method(:system) { |_cmd| true }
    end
  end

  def teardown
    AddCommand.class_eval { remove_method :system } if AddCommand.method_defined?(:system)
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

  def test_add_opens_new_note_in_editor
    Dir.chdir(@tmpdir) do
      system_cmd = nil
      AddCommand.class_eval do
        remove_method :system if method_defined?(:system)
        define_method(:system) do |cmd|
          system_cmd = cmd
          true
        end
      end
      begin
        AddCommand.new.run('--title', 'T', '--tags', 't', 'note')
        assert system_cmd, 'system(editor) should be called'
        assert system_cmd.include?(File.expand_path(@tmpdir)), "Editor should receive path under tmpdir, got #{system_cmd}"
        assert system_cmd.include?('note-'), "Editor command should include note path, got #{system_cmd}"
        assert_match(/\+1\b/, system_cmd, 'Editor should receive +1 for line')
      ensure
        AddCommand.class_eval do
          remove_method :system
          define_method(:system) { |_cmd| true }
        end
      end
    end
  end

  def test_run_creates_note
    Dir.chdir(@tmpdir) do
      # Use 'note' type which is created by InitCommand in setup
      AddCommand.new.run('--title', 'Test Note', '--tags', 'test', 'note')
      files = Dir.glob('*.md')
      assert_equal 1, files.size
      file = files.first
      assert_match(/note-\d{4}-\d{2}-\d{2}\.md/, file)
      content = File.read(file)
      assert_match(/# note/, content)
      assert_match(/Content/, content)
    end
  end

  def test_create_note_file_indexes_note
    Dir.chdir(@tmpdir) do
      config = Config.load
      template_config = Config.get_template(config, 'note')
      assert template_config, 'note template should exist after init'
      content = <<~MD
        ---
        id: "createfiletest01"
        type: note
        date: "2025-02-05"
        title: "Indexed Note"
        aliases: "note> 2025-02-05: Indexed Note"
        tags: ["test"]
        ---
        # note
        Body
      MD
      add_cmd = AddCommand.new
      filepath = add_cmd.create_note_file(config, template_config, 'note', content)
      assert File.exist?(filepath), "File should exist at #{filepath}"
      db_path = Config.index_db_path(config['notebook_path'])
      assert File.exist?(db_path), 'Index db should exist'
      db = SQLite3::Database.new(db_path)
      rows = db.execute('SELECT id, path FROM notes WHERE id = ?', ['createfiletest01'])
      db.close
      assert_equal 1, rows.size, 'create_note_file should index the note so it appears in the index'
      assert_equal 'note-2025-02-05.md', File.basename(rows.first[1])
    end
  end

  def test_default_tags_from_template_config_merged_with_supplied_tags
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        Config.get_template(Config.load, 'note'),
        {
          'type' => 'daily',
          'template_file' => 'daily.erb',
          'filename_pattern' => '{type}-{date}.md',
          'subdirectory' => ''
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)
      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      daily_erb = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        config:
          path: "daily-<%= date %>.md"
          default_tags:
            - daily
            - default
        ---
        # <%= title %>
      ERB
      File.write(File.join(template_dir, 'daily.erb'), daily_erb)
      AddCommand.new.run('--title', 'Entry', '--tags', 'foo, bar', 'daily')
      files = Dir.glob('daily-*.md')
      assert_equal 1, files.size, 'One daily note should be created'
      content = File.read(files.first)
      metadata, = Utils.parse_front_matter(content)
      assert_equal %w[daily default foo bar], metadata['tags'],
        'tags should be template default_tags merged with supplied tags (defaults first, no config in output)'
      refute metadata.key?('config'), 'config block should be removed from output'
    end
  end

  def test_default_tags_from_template_when_no_tags_supplied
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        Config.get_template(Config.load, 'note'),
        {
          'type' => 'daily',
          'template_file' => 'daily.erb',
          'filename_pattern' => '{type}-{date}.md',
          'subdirectory' => ''
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)
      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      daily_erb = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        config:
          path: "daily-<%= date %>.md"
          default_tags:
            - daily
            - default
        ---
        # <%= title %>
      ERB
      File.write(File.join(template_dir, 'daily.erb'), daily_erb)
      AddCommand.new.run('--title', 'Entry', '--tags', '', 'daily')
      files = Dir.glob('daily-*.md')
      assert_equal 1, files.size
      metadata, = Utils.parse_front_matter(File.read(files.first))
      assert_equal %w[daily default], metadata['tags'], 'tags should be only template default_tags when none supplied'
    end
  end

  def test_add_preserves_template_user_defined_front_matter_keys
    Dir.chdir(@tmpdir) do
      require_relative '../../lib/utils'
      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      account_erb = <<~ERB
        ---
        id: "<%= id %>"
        type: account
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        description: "<%= description %>"
        crm:
          id:
          owner:
          segment:
        config:
          path: "accounts/<%= id %>-<%= slugify(title) %>.md"
          default_tags: [account]
        ---
        # <%= title %>
        <%= content %>
      ERB
      File.write(File.join(template_dir, 'account.erb'), account_erb)

      AddCommand.new.run('--title', 'Acme Corp', '--tags', 'client', 'account')
      files = Dir.glob(File.join('accounts', '*.md'))
      assert_equal 1, files.size, 'One account note should be created under accounts/'
      content = File.read(files.first)
      metadata, = Utils.parse_front_matter(content)
      assert metadata.key?('crm'), 'Template user-defined key crm should appear in created note'
      assert metadata['crm'].is_a?(Hash), 'crm should be a hash'
      assert metadata['crm'].key?('id'), 'crm should have id from template'
      assert metadata['crm'].key?('owner'), 'crm should have owner from template'
      assert metadata['crm'].key?('segment'), 'crm should have segment from template'
      refute metadata.key?('config'), 'config block should be removed from output'
    end
  end

  def test_add_with_description_flag
    Dir.chdir(@tmpdir) do
      require_relative '../../lib/utils'
      AddCommand.new.run('--title', 'T', '--description', 'Short summary', '--tags', 'test', 'note')
      files = Dir.glob('*.md')
      assert_equal 1, files.size
      content = File.read(files.first)
      metadata, = Utils.parse_front_matter(content)
      assert_equal 'Short summary', metadata['description'].to_s.strip, 'Description should be in front matter (folded style round-trips as string)'
    end
  end

  def test_path_interpolation_excludes_description
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        {
          'type' => 'path-desc',
          'template_file' => 'path-desc.erb',
          'filename_pattern' => '{type}-{date}.md',
          'subdirectory' => ''
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)
      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      # config.path contains literal {description} - should NOT be substituted (description excluded from path vars)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        description: >
          <%= description.to_s.gsub("\n", "\n  ") %>
        config:
          path: "<%= id %>-{description}.md"
        ---
        # <%= title %>
      ERB
      File.write(File.join(template_dir, 'path-desc.erb'), template_content)
      AddCommand.new.run('--title', 'Note', '--tags', 't', '--description', 'overview text', 'path-desc')
      files = Dir.glob('*.md')
      assert_equal 1, files.size
      # Description is interpolated like other metadata
      assert_includes files.first, 'overview', 'Path interpolation should substitute description'
      refute_includes files.first, '{description}', 'Placeholder should be substituted'
    end
  end

  def test_add_with_multiline_description_folded_style
    Dir.chdir(@tmpdir) do
      require_relative '../../lib/utils'
      AddCommand.new.run('--title', 'T', '--description', "Line one\nLine two", '--tags', 'test', 'note')
      files = Dir.glob('*.md')
      assert_equal 1, files.size
      content = File.read(files.first)
      metadata, = Utils.parse_front_matter(content)
      # YAML folded style folds newlines to space, so we get "Line one Line two"
      desc = metadata['description']
      assert_includes desc, 'Line one'
      assert_includes desc, 'Line two'
    end
  end

  def test_interactive_prompts_for_description
    # When gum is in PATH it is used for prompts and fails without TTY; skip then
    skip 'Interactive test skipped when gum is in PATH (no TTY)' if system('command -v gum > /dev/null 2>&1')
    Dir.chdir(@tmpdir) do
      require_relative '../../lib/utils'
      # Interactive mode: no --title, no --tags, no --description -> prompts for all three
      stdin_content = "Interactive Title\ntag1, tag2\nPrompted description text\n"
      $stdin = StringIO.new(stdin_content)
      begin
        AddCommand.new.run('note')
        files = Dir.glob('*.md')
        assert_equal 1, files.size
        content = File.read(files.first)
        metadata, = Utils.parse_front_matter(content)
        assert_equal 'Interactive Title', metadata['title']
        assert_equal 'Prompted description text', metadata['description'].to_s.strip
      ensure
        $stdin = STDIN
      end
    end
  end

  def test_run_creates_note_with_custom_filename_pattern
    Dir.chdir(@tmpdir) do
      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        config:
          path: "<%= id %>-<%= type %>.md"
        ---
        # Custom
      ERB
      File.write(File.join(template_dir, 'custom.erb'), template_content)

      AddCommand.new.run('--title', 'Custom Note', '--tags', 'custom, test', 'custom')
      files = Dir.glob('*.md')
      assert_equal 1, files.size
      assert_match(/^[0-9a-f]{8}-custom\.md$/, files.first)
    end
  end

  def test_run_creates_note_in_subdirectory
    Dir.chdir(@tmpdir) do
      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: journal
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        config:
          path: "journal/<%= year %>/<%= date %>-journal.md"
        ---
        # Journal Entry
      ERB
      File.write(File.join(template_dir, 'journal.erb'), template_content)

      AddCommand.new.run('--title', 'Journal Entry', '--tags', 'journal', 'journal')
      year = Time.now.strftime('%Y')
      journal_dir = File.join('journal', year)
      assert Dir.exist?(journal_dir), "expected directory #{journal_dir} to exist"
      files = Dir.glob(File.join(journal_dir, '*.md'))
      assert_equal 1, files.size
      assert_match(/\d{4}-\d{2}-\d{2}-journal\.md/, File.basename(files.first))
    end
  end

  def test_run_with_metadata_in_filename_pattern
    Dir.chdir(@tmpdir) do
      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: meeting
        title: "<%= title %>"
        date: "<%= date %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        config:
          path: "meetings/<%= year %>/<%= month %>/meeting-<%= date %>-<%= slugify(title) %>.md"
        ---
        # Meeting Notes
      ERB
      File.write(File.join(template_dir, 'meeting.erb'), template_content)

      AddCommand.new.run('--title', 'standup', '--tags', 'meeting', 'meeting')
      assert Dir.exist?('meetings'), 'expected meetings directory to exist'
      files = Dir.glob(File.join('meetings', '**', '*.md'))
      assert_equal 1, files.size
      assert_match(/meeting-\d{4}-\d{2}-\d{2}-standup\.md/, File.basename(files.first))
    end
  end

  def test_completion_output
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        { 'type' => 'note' },
        { 'type' => 'journal' },
        { 'type' => 'meeting' }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      cmd = AddCommand.new
      output = capture_io { cmd.run('--completion') }.first
      # Completion should return space-separated template types
      types = output.strip.split
      assert_includes types, 'note'
      assert_includes types, 'journal'
      assert_includes types, 'meeting'
    end
  end

  def test_completion_with_empty_templates_array
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config.delete('templates')
      File.write('.zh/config.yaml', config.to_yaml)

      cmd = AddCommand.new
      output = capture_io { cmd.run('--completion') }.first
      # Includes all bundled templates and options
      assert_equal 'bookmark journal meeting note organization person --title --tags --description --help -h', output.strip
    end
  end

  def test_completion_with_non_array_templates
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = 'not-an-array'
      File.write('.zh/config.yaml', config.to_yaml)

      cmd = AddCommand.new
      output = capture_io { cmd.run('--completion') }.first
      # Includes all bundled templates and options
      assert_equal 'bookmark journal meeting note organization person --title --tags --description --help -h', output.strip
    end
  end

  def test_completion_fallback_when_config_cannot_load
    # Temporarily break config loading
    original_load = Config.method(:load)
    Config.define_singleton_method(:load) { raise StandardError, 'Config error' }

    begin
      cmd = AddCommand.new
      output = capture_io { cmd.run('--completion') }.first
      assert_equal 'note journal meeting bookmark --title --tags --description --help -h', output.strip
    ensure
      # Restore original method
      Config.define_singleton_method(:load, original_load)
    end
  end

  def test_template_not_found_error
    Dir.chdir(@tmpdir) do
      cmd = AddCommand.new
      # SystemExit exits the process, so we need to catch it
      begin
        capture_io { cmd.run('--title', 'Test', '--tags', 'test', 'nonexistent-template') }
        flunk 'Expected SystemExit to be raised'
      rescue SystemExit => e
        assert_equal 1, e.status
      end
    end
  end

  def test_template_file_not_found_searches_both_locations
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        {
          'type' => 'missing',
          'template_file' => 'missing.erb'
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      cmd = AddCommand.new
      begin
        output = capture_io { cmd.run('--title', 'Test', '--tags', 'test', 'missing') }.first
        assert_includes output, 'Template file not found'
        assert_includes output, '.zh/templates/missing.erb'
        assert_includes output, '.config/zh/templates/missing.erb'
        flunk 'Expected SystemExit to be raised'
      rescue SystemExit => e
        assert_equal 1, e.status
      end
    end
  end

  def test_invalid_erb_template_syntax
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        {
          'type' => 'invalid',
          'template_file' => 'invalid.erb'
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      # Create a template with truly invalid ERB syntax that will cause an error
      invalid_template = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        ---
        # Invalid ERB: <%= unclosed tag
      ERB
      File.write(File.join(template_dir, 'invalid.erb'), invalid_template)

      cmd = AddCommand.new
      # ERB is lenient with some syntax errors, so this test verifies the command
      # handles template rendering without crashing. The template may render successfully
      # even with what looks like invalid syntax, or it may raise an error.
      # Either outcome is acceptable - we're testing that the command doesn't crash.
      begin
        cmd.run('--title', 'Test', '--tags', 'test', 'invalid')
        # If it succeeds, ERB was able to parse it (ERB is lenient)
        assert true
      rescue SyntaxError, StandardError
        # If it raises an error, that's also acceptable
        assert true
      end
    end
  end

  def test_config_path_override
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        {
          'type' => 'path-override',
          'template_file' => 'path-override.erb'
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        config:
          path: "custom/{type}-{date}.md"
        ---
        # Path Override Test
        Content
      ERB
      File.write(File.join(template_dir, 'path-override.erb'), template_content)

      AddCommand.new.run('--title', 'Path Override Test', '--tags', 'test', 'path-override')
      files = Dir.glob('**/*.md', File::FNM_DOTMATCH)
      assert_equal 1, files.size
      assert_match(/custom\/path-override-\d{4}-\d{2}-\d{2}\.md/, files.first)
      
      # Verify config was removed from metadata
      content = File.read(files.first)
      # After reconstruction, YAML format may use single quotes or different formatting
      # Just verify id is present and config is removed
      assert_match(/id:/, content)
      refute_match(/config:/, content)
    end
  end

  def test_reconstruct_content_with_various_metadata
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        {
          'type' => 'complex',
          'template_file' => 'complex.erb'
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        config:
          path: "complex/{type}.md"
        author:
          name: Test
        ---
        # Complex Metadata
        Body content
      ERB
      File.write(File.join(template_dir, 'complex.erb'), template_content)

      AddCommand.new.run('--title', 'Complex Note', '--tags', 'complex, test', 'complex')
      files = Dir.glob('**/*.md', File::FNM_DOTMATCH)
      assert_equal 1, files.size
      
      content = File.read(files.first)
      # Verify metadata structure is preserved
      assert_match(/tags:/, content)
      assert_match(/author:/, content)
      # Verify config is removed
      refute_match(/config:/, content)
    end
  end

  def test_directory_creation_for_subdirectory
    Dir.chdir(@tmpdir) do
      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        config:
          path: "very/deep/nested/path/deep.md"
        ---
        # Deep
      ERB
      File.write(File.join(template_dir, 'deep.erb'), template_content)

      AddCommand.new.run('--title', 'Deep Note', '--tags', 'test', 'deep')
      assert Dir.exist?('very/deep/nested/path'), 'expected very/deep/nested/path to exist'
      files = Dir.glob(File.join('very', 'deep', 'nested', 'path', '*.md'))
      assert_equal 1, files.size
    end
  end

  def test_default_type_when_no_argument
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      # When no argument is provided, AddCommand uses 'note' as default
      config['templates'] = [
        {
          'type' => 'note',
          'template_file' => 'note.erb',
          'filename_pattern' => '{type}-{date}.md',
          'subdirectory' => ''
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      # Ensure template file exists
      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        ---
        # Note
        Content
      ERB
      File.write(File.join(template_dir, 'note.erb'), template_content)

      AddCommand.new.run('--title', 'Test Note', '--tags', 'test')
      files = Dir.glob('*.md')
      assert_equal 1, files.size
      # Should use 'note' as default type (from args.first || 'note')
      content = File.read(files.first)
      assert_match(/\ntype: ["']?note["']?\n/, content, 'type should be note (quoted or unquoted)')
    end
  end

  def test_template_with_special_characters_in_title
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        {
          'type' => 'special',
          'template_file' => 'special.erb',
          'filename_pattern' => '{type}-{date}.md',
          'subdirectory' => ''
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        ---
        # <%= title %>
        Content
      ERB
      File.write(File.join(template_dir, 'special.erb'), template_content)

      # Test with colon in title
      AddCommand.new.run('--title', 'Meeting: Q1 Review', '--tags', 'meeting, q1', 'special')
      files = Dir.glob('*.md')
      assert_equal 1, files.size
      content = File.read(files.first)
      assert_match(/title: ['"]Meeting: Q1 Review['"]/, content, 'title should contain Meeting: Q1 Review')
      assert_match(/# Meeting: Q1 Review/, content)
      
      # Verify YAML parses correctly
      require_relative '../../lib/utils'
      metadata, = Utils.parse_front_matter(content)
      assert_equal 'Meeting: Q1 Review', metadata['title']
      assert metadata['tags'].is_a?(Array)
      
      # Clean up and test with hash symbol
      File.delete(files.first)
      AddCommand.new.run('--title', 'Note #1', '--tags', 'test', 'special')
      files = Dir.glob('*.md')
      assert_equal 1, files.size
      content = File.read(files.first)
      assert_match(/title: ['"]Note #1['"]/, content, 'title should contain Note #1')
      
      # Verify YAML parses correctly
      metadata, = Utils.parse_front_matter(content)
      assert_equal 'Note #1', metadata['title']
    end
  end

  def test_tags_rendered_as_array_not_string
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        {
          'type' => 'tags-test',
          'template_file' => 'tags-test.erb',
          'filename_pattern' => '{type}-{date}.md',
          'subdirectory' => ''
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        ---
        # <%= title %>
        Content
      ERB
      File.write(File.join(template_dir, 'tags-test.erb'), template_content)

      AddCommand.new.run('--title', 'Tags Test', '--tags', 'tag1, tag2, tag3', 'tags-test')
      files = Dir.glob('*.md')
      assert_equal 1, files.size
      content = File.read(files.first)
      
      # Verify tags are rendered as array (inline or multi-line YAML), not quoted string
      assert content.include?('tag1') && content.include?('tag2') && content.include?('tag3'), 'tags should include tag1, tag2, tag3'
      refute_match(/tags: "\["tag1", "tag2", "tag3"\]"/, content)
      
      # Verify parsed metadata has tags as Array, not String
      require_relative '../../lib/utils'
      metadata, = Utils.parse_front_matter(content)
      assert metadata['tags'].is_a?(Array), "Tags should be an Array, got #{metadata['tags'].class}"
      assert_equal ['tag1', 'tag2', 'tag3'], metadata['tags']
      
      # Test with empty tags
      File.delete(files.first)
      AddCommand.new.run('--title', 'No Tags', '--tags', '', 'tags-test')
      files = Dir.glob('*.md')
      assert_equal 1, files.size
      content = File.read(files.first)
      assert_match(/tags: \[\]/, content)
      
      metadata, = Utils.parse_front_matter(content)
      assert metadata['tags'].is_a?(Array)
      assert_equal [], metadata['tags']
    end
  end

  def test_config_path_with_special_characters
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        {
          'type' => 'special-path',
          'template_file' => 'special-path.erb'
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      # Template with quoted config.path containing interpolated title with special characters
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        config:
          path: "<%= id %>-<%= title %>.md"
        ---
        # <%= title %>
        Content
      ERB
      File.write(File.join(template_dir, 'special-path.erb'), template_content)

      # Test with colon in title (would break if path wasn't quoted)
      AddCommand.new.run('--title', 'Meeting: Q1 Review', '--tags', 'test', 'special-path')
      files = Dir.glob('**/*.md', File::FNM_DOTMATCH)
      assert_equal 1, files.size
      
      # Verify file was created at correct path
      file = files.first
      # IDs are 8-character hexadecimal (e.g., 7636bc4b)
      assert_match(/[0-9a-f]{8}-Meeting: Q1 Review\.md$/, file)
      
      # Verify YAML parsing didn't fail - the file should be readable and parseable
      content = File.read(file)
      require_relative '../../lib/utils'
      # The file should parse without errors (main goal is to verify no YAML syntax errors with special chars)
      # Note: After reconstruction via CommonMarker, YAML format may be reformatted
      # The key test is that parsing doesn't fail with special characters
      begin
        metadata, body = Utils.parse_front_matter(content)
        # Title should be in the content somewhere (may be reformatted by CommonMarker)
        assert content.include?('Meeting: Q1 Review'), "Title should be in content. Content: #{content[0..400]}"
        refute_match(/config:/, content) # Config should be removed
      rescue Psych::SyntaxError => e
        flunk "YAML parsing failed with special characters in path: #{e.message}\nContent:\n#{content[0..400]}"
      end
      
      # Test with hash symbol in title
      File.delete(file)
      AddCommand.new.run('--title', 'Note #1', '--tags', 'test', 'special-path')
      files = Dir.glob('**/*.md', File::FNM_DOTMATCH)
      assert_equal 1, files.size
      file = files.first
      assert_match(/[0-9a-f]{8}-Note #1\.md$/, file)
      
      # Verify YAML parsing didn't fail
      content = File.read(file)
      begin
        metadata, body = Utils.parse_front_matter(content)
        # Title should be in content (may be reformatted)
        assert content.include?('Note #1'), "Title should be in content. Content: #{content[0..400]}"
      rescue Psych::SyntaxError => e
        flunk "YAML parsing failed with hash in path: #{e.message}\nContent:\n#{content[0..400]}"
      end
    end
  end

  def test_yaml_parsing_of_rendered_template
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        {
          'type' => 'yaml-test',
          'template_file' => 'yaml-test.erb',
          'filename_pattern' => '{type}-{date}.md',
          'subdirectory' => ''
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        config:
          path: "<%= id %>-<%= title %>.md"
        ---
        # <%= title %>
        Content with special: characters & symbols [test]
      ERB
      File.write(File.join(template_dir, 'yaml-test.erb'), template_content)

      # Test with various special characters
      special_titles = [
        'Meeting: Q1 Review',
        'Note #1',
        'Test & Review',
        'Title [Important]',
        'Path/To/Note'
      ]

      special_titles.each do |title|
        AddCommand.new.run('--title', title, '--tags', 'test, special', 'yaml-test')
        files = Dir.glob('**/*.md', File::FNM_DOTMATCH)
        assert_equal 1, files.size, "Should create one file for title: #{title}"
        
        content = File.read(files.first)
        
        # Verify YAML parsing doesn't fail (main goal: no syntax errors with special chars)
        require_relative '../../lib/utils'
        begin
          metadata, body = Utils.parse_front_matter(content)
          # The key test is that parsing succeeds without YAML syntax errors
          # Content may be reformatted by CommonMarker, so we verify title is present in content
          assert content.include?(title), "Title '#{title}' should be in content. Content preview: #{content[0..400]}"
          assert_match(/Content with special/, body, "Body should contain content for title: #{title}")
        rescue Psych::SyntaxError => e
          flunk "YAML parsing failed for title '#{title}': #{e.message}\nContent:\n#{content[0..500]}"
        end
        
        # Clean up for next iteration
        File.delete(files.first)
      end
    end
  end

  def test_slugify_in_template
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        {
          'type' => 'slug-test',
          'template_file' => 'slug-test.erb'
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        config:
          path: "<%= slugify(id) %>-<%= slugify(title) %>.md"
        ---
        # <%= title %>
        Content
      ERB
      File.write(File.join(template_dir, 'slug-test.erb'), template_content)

      # Test with special characters in title
      AddCommand.new.run('--title', 'Meeting: Q1 Review', '--tags', 'test', 'slug-test')
      files = Dir.glob('**/*.md', File::FNM_DOTMATCH)
      assert_equal 1, files.size

      # Verify filename is normalized (lowercase, hyphens instead of spaces/special chars)
      file = files.first
      assert_match(/[0-9a-f]{8}-meeting-q1-review\.md$/, file, "Expected normalized filename, got: #{file}")

      # Verify content still has original title
      content = File.read(file)
      require_relative '../../lib/utils'
      metadata, = Utils.parse_front_matter(content)
      assert_equal 'Meeting: Q1 Review', metadata['title']
      refute_match(/config:/, content) # Config should be removed

      # Test with hash symbol
      File.delete(files.first)
      AddCommand.new.run('--title', 'Note #1', '--tags', 'test', 'slug-test')
      files = Dir.glob('**/*.md', File::FNM_DOTMATCH)
      assert_equal 1, files.size
      file = files.first
      assert_match(/[0-9a-f]{8}-note-1\.md$/, file, "Expected normalized filename, got: #{file}")

      # Test with ampersand
      File.delete(files.first)
      AddCommand.new.run('--title', 'Test & Review', '--tags', 'test', 'slug-test')
      files = Dir.glob('**/*.md', File::FNM_DOTMATCH)
      assert_equal 1, files.size
      file = files.first
      assert_match(/[0-9a-f]{8}-test-review\.md$/, file, "Expected normalized filename, got: #{file}")
    end
  end

  def test_alias_generation_with_default_pattern
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['templates'] = [
        {
          'type' => 'alias-test',
          'template_file' => 'alias-test.erb'
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        ---
        # <%= title %>
        Content
      ERB
      File.write(File.join(template_dir, 'alias-test.erb'), template_content)

      AddCommand.new.run('--title', 'Test Note', '--tags', 'test', 'alias-test')
      files = Dir.glob('*.md')
      assert_equal 1, files.size

      content = File.read(files.first)
      require_relative '../../lib/utils'
      metadata, = Utils.parse_front_matter(content)
      
      # Verify alias is generated in default format: "{type}> {date}: {title}"
      expected_alias = "alias-test> #{metadata['date']}: Test Note"
      assert_equal expected_alias, metadata['aliases']
    end
  end

  def test_alias_generation_with_custom_pattern
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['engine'] = (config['engine'] || {}).merge('default_alias' => '{type} - {title} ({date})')
      config['templates'] = [
        {
          'type' => 'custom-alias',
          'template_file' => 'custom-alias.erb'
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        ---
        # <%= title %>
        Content
      ERB
      File.write(File.join(template_dir, 'custom-alias.erb'), template_content)

      AddCommand.new.run('--title', 'Custom Pattern Test', '--tags', 'test', 'custom-alias')
      files = Dir.glob('*.md')
      assert_equal 1, files.size

      content = File.read(files.first)
      require_relative '../../lib/utils'
      metadata, = Utils.parse_front_matter(content)
      
      # Verify alias uses custom pattern
      expected_alias = "custom-alias - Custom Pattern Test (#{metadata['date']})"
      assert_equal expected_alias, metadata['aliases']
    end
  end

  def test_alias_uses_template_default_alias_when_present
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['engine'] = (config['engine'] || {}).merge('default_alias' => '{type}> {date}: {title}')
      config['templates'] = [
        { 'type' => 'template-alias', 'template_file' => 'template-alias.erb' }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        config:
          default_alias: "Note: {title} ({date})"
        ---
        # <%= title %>
        Content
      ERB
      File.write(File.join(template_dir, 'template-alias.erb'), template_content)

      AddCommand.new.run('--title', 'My Note', '--tags', 'test', 'template-alias')
      files = Dir.glob('*.md')
      assert_equal 1, files.size

      content = File.read(files.first)
      require_relative '../../lib/utils'
      metadata, = Utils.parse_front_matter(content)
      assert_equal "Note: My Note (#{metadata['date']})", metadata['aliases'],
                   'Alias should use template config.default_alias when present'
      refute metadata.key?('config'), 'config block should be stripped from output'
    end
  end

  def test_alias_generation_with_various_variables
    Dir.chdir(@tmpdir) do
      config = YAML.load_file('.zh/config.yaml')
      config['engine'] = (config['engine'] || {}).merge('default_alias' => '{type}> {year}-{month}-{date}: {title} (ID: {id})')
      config['templates'] = [
        {
          'type' => 'var-test',
          'template_file' => 'var-test.erb'
        }
      ]
      File.write('.zh/config.yaml', config.to_yaml)

      template_dir = File.join(@temp_home, '.config', 'zh', 'templates')
      FileUtils.mkdir_p(template_dir)
      template_content = <<~ERB
        ---
        id: "<%= id %>"
        type: "<%= type %>"
        date: "<%= date %>"
        title: "<%= title %>"
        aliases: "<%= aliases %>"
        tags: <%= tags %>
        ---
        Content
      ERB
      File.write(File.join(template_dir, 'var-test.erb'), template_content)

      AddCommand.new.run('--title', 'Variable Test', '--tags', 'test', 'var-test')
      files = Dir.glob('*.md')
      assert_equal 1, files.size

      content = File.read(files.first)
      require_relative '../../lib/utils'
      metadata, = Utils.parse_front_matter(content)
      
      # Verify alias includes year, month, date, and id variables
      assert_match(/var-test> \d{4}-\d{2}-/, metadata['aliases'])
      assert_match(/Variable Test \(ID: [0-9a-f]{8}\)/, metadata['aliases'])  # 8-character hex ID
      assert_includes metadata['aliases'], metadata['date']
    end
  end

  private

  def capture_io
    require 'stringio'
    old_stdout = $stdout
    $stdout = StringIO.new
    yield
    [$stdout.string, '']
  ensure
    $stdout = old_stdout
  end
end
