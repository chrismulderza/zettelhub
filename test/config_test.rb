require 'minitest/autorun'
require 'tempfile'
require 'fileutils'
require_relative '../lib/config'
require_relative '../lib/utils'

class ConfigTest < Minitest::Test
  def setup
    @temp_home = Dir.mktmpdir
    @temp_dir = Dir.mktmpdir
    @original_pwd = Dir.pwd
    @original_home = ENV['HOME']
    @original_notebook_path = ENV['ZH_NOTEBOOK_PATH']
    ENV['HOME'] = @temp_home
    ENV.delete('ZH_NOTEBOOK_PATH')
    @global_config_file = File.join(@temp_home, '.config', 'zh', 'config.yaml')
    @original_config_file = Config::CONFIG_FILE
    Config.send(:remove_const, :CONFIG_FILE)
    Config.const_set(:CONFIG_FILE, @global_config_file)
  end

  def teardown
    FileUtils.rm_rf(@temp_home)
    FileUtils.rm_rf(@temp_dir)
    Dir.chdir(@original_pwd)
    ENV['HOME'] = @original_home if @original_home
    if @original_notebook_path
      ENV['ZH_NOTEBOOK_PATH'] = @original_notebook_path
    else
      ENV.delete('ZH_NOTEBOOK_PATH')
    end
    Config.send(:remove_const, :CONFIG_FILE)
    Config.const_set(:CONFIG_FILE, @original_config_file)
  end

  def test_load_global_config_only
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    config_content = { 'notebook_path' => '/path/to/notebook' }
    File.write(@global_config_file, config_content.to_yaml)
    Dir.chdir(@temp_dir) do
      config = Config.load
      assert_equal '/path/to/notebook', config['notebook_path']
    end
  end

  def test_load_merges_local_config
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    global_config = { 'notebook_path' => @temp_dir, 'global_key' => 'global' }
    File.write(@global_config_file, global_config.to_yaml)
    Dir.chdir(@temp_dir) do
      FileUtils.mkdir_p('.zh')
      local_config = { 'local_key' => 'local' }
      File.write('.zh/config.yaml', local_config.to_yaml)
      config = Config.load
      assert_equal File.realpath(@temp_dir), File.realpath(config['notebook_path'])
      assert_equal 'global', config['global_key']
      assert_equal 'local', config['local_key']
    end
  end

  def test_load_raises_when_no_config_found
    Dir.chdir(@temp_dir) do
      # No config anywhere should raise error
      error = assert_raises(RuntimeError) do
        Config.load
      end
      assert_match(/No config file found/, error.message)
      assert_match(/Searched locations/, error.message)
    end
  end

  def test_load_config_returns_nil_for_missing_file
    result = Config.load_config('/nonexistent/file.yaml')
    assert_nil result
  end

  def test_path_helpers
    notebook = '/path/to/notebook'
    assert_equal File.join(notebook, '.zh'), Config.zh_dir(notebook)
    assert_equal File.join(notebook, '.zh', 'config.yaml'), Config.local_config_path(notebook)
    assert_equal File.join(notebook, '.zh', 'index.db'), Config.index_db_path(notebook)
    assert_equal File.join(notebook, '.zh', 'templates'), Config.local_templates_dir(notebook)
    # global_templates_dir uses config_dir_at_runtime (respects ENV['HOME'] set in setup)
    assert_equal File.join(Config.config_dir_at_runtime, 'templates'), Config.global_templates_dir
  end

  def test_get_template_with_new_hash_format
    # Discovery: notebook_path and template dirs; type from template front matter
    notebook = File.join(@temp_dir, 'nb')
    FileUtils.mkdir_p(File.join(notebook, '.zh', 'templates'))
    File.write(File.join(notebook, '.zh', 'templates', 'journal.erb'), "---\ntype: journal\ndate: \"\"\n---\n")
    config = { 'notebook_path' => notebook }
    template = Config.get_template(config, 'journal')
    assert template, 'journal template should be found via discovery'
    assert_equal 'journal', template['type']
    assert_equal 'journal.erb', template['template_file']
  end

  def test_get_template_with_defaults
    notebook = File.join(@temp_dir, 'nb2')
    FileUtils.mkdir_p(File.join(notebook, '.zh', 'templates'))
    File.write(File.join(notebook, '.zh', 'templates', 'minimal.erb'), "---\ntype: minimal\n---\n")
    config = { 'notebook_path' => notebook }
    template = Config.get_template(config, 'minimal')
    assert template, 'minimal template should be found via discovery'
    assert_equal 'minimal', template['type']
    assert_equal 'minimal.erb', template['template_file']
  end

  def test_get_template_returns_nil_for_nonexistent_template
    config = { 'notebook_path' => @temp_dir }
    template = Config.get_template(config, 'nonexistent')
    assert_nil template
  end

  def test_default_template_types
    assert_equal %w[note journal meeting bookmark], Config.default_template_types
  end

  def test_template_types_returns_sorted_unique_list
    config = { 'notebook_path' => @temp_dir }
    types = Config.template_types(config)
    assert_includes types, 'note'
    assert_includes types, 'journal'
    assert_includes types, 'meeting'
    assert_equal types.sort, types
  end

  def test_template_types_returns_empty_for_nil_config
    assert_equal [], Config.template_types(nil)
  end

  def test_template_types_returns_empty_for_no_templates
    assert_equal [], Config.template_types({})
    assert_equal [], Config.template_types('templates' => [])
  end

  def test_load_with_invalid_yaml_in_global_config
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    File.write(@global_config_file, 'invalid: yaml: content: [unclosed')
    Dir.chdir(@temp_dir) do
      assert_raises(Psych::SyntaxError) do
        Config.load
      end
    end
  end

  def test_load_with_invalid_yaml_in_local_config
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    global_config = { 'notebook_path' => @temp_dir, 'templates' => ['default'] }
    File.write(@global_config_file, global_config.to_yaml)
    Dir.chdir(@temp_dir) do
      FileUtils.mkdir_p('.zh')
      File.write('.zh/config.yaml', 'invalid: yaml: [unclosed')
      assert_raises(Psych::SyntaxError) do
        Config.load
      end
    end
  end

  def test_load_with_missing_notebook_path_in_global_config
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    config_content = { 'templates' => ['default'] }
    File.write(@global_config_file, config_content.to_yaml)
    Dir.chdir(@temp_dir) do
      # Missing notebook_path in global config should raise an error
      assert_raises(RuntimeError) do
        Config.load
      end
    end
  end

  def test_load_expands_relative_notebook_path
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    relative_path = '../relative-notebook'
    config_content = { 'notebook_path' => relative_path, 'templates' => ['default'] }
    File.write(@global_config_file, config_content.to_yaml)
    Dir.chdir(@temp_dir) do
      config = Config.load
      # Should expand to absolute path
      assert File.expand_path(relative_path, @temp_dir) == config['notebook_path'] ||
             File.expand_path(relative_path) == config['notebook_path']
    end
  end

  def test_get_template_with_string_array_old_format
    config = { 'templates' => ['note', 'journal', 'meeting'] }
    template = Config.get_template(config, 'note')
    assert_nil template
  end

  def test_get_template_with_empty_templates_array
    config = { 'templates' => [], 'notebook_path' => @temp_dir }
    template = Config.get_template(config, 'nonexistent-type')
    assert_nil template
  end

  def test_get_template_with_nil_templates
    config = { 'templates' => nil }
    template = Config.get_template(config, 'any')
    assert_nil template
  end

  def test_get_template_with_non_array_templates
    config = { 'templates' => 'not-an-array' }
    template = Config.get_template(config, 'any')
    assert_nil template
  end

  def test_get_template_with_non_hash_items
    config = { 'notebook_path' => @temp_dir }
    template1 = Config.get_template(config, 'note')
    assert template1, 'note should be found via discovery'
    assert_equal 'note', template1['type']
    template2 = Config.get_template(config, 'journal')
    assert template2, 'journal should be found via discovery'
    assert_equal 'journal', template2['type']
  end

  def test_get_template_with_missing_type
    config = { 'notebook_path' => @temp_dir }
    template = Config.get_template(config, 'nonexistent-type')
    assert_nil template
  end

  def test_normalize_template_with_all_defaults
    template = { 'type' => 'test' }
    normalized = Config.normalize_template(template)
    assert_equal 'test', normalized['type']
    assert_equal 'test.erb', normalized['template_file']
  end

  def test_normalize_template_with_partial_overrides
    template = {
      'type' => 'custom',
      'template_file' => 'custom-template.erb'
    }
    normalized = Config.normalize_template(template)
    assert_equal 'custom', normalized['type']
    assert_equal 'custom-template.erb', normalized['template_file']
  end

  def test_normalize_template_with_all_overrides
    template = {
      'type' => 'full',
      'template_file' => 'full.erb'
    }
    normalized = Config.normalize_template(template)
    assert_equal 'full', normalized['type']
    assert_equal 'full.erb', normalized['template_file']
  end

  def test_load_expands_notebook_path_to_absolute
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    absolute_path = File.expand_path(@temp_dir)
    config_content = { 'notebook_path' => absolute_path, 'templates' => ['default'] }
    File.write(@global_config_file, config_content.to_yaml)
    Dir.chdir(@temp_dir) do
      config = Config.load
      assert_equal absolute_path, config['notebook_path']
    end
  end

  def test_load_merges_nested_structures_shallowly
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    global_tpl = File.join(config_dir, 'templates')
    FileUtils.mkdir_p(global_tpl)
    File.write(File.join(global_tpl, 'global.erb'), "---\ntype: global-template\n---\n")
    global_config = {
      'notebook_path' => @temp_dir,
      'other_key' => 'global-value'
    }
    File.write(@global_config_file, global_config.to_yaml)
    Dir.chdir(@temp_dir) do
      FileUtils.mkdir_p('.zh/templates')
      File.write('.zh/templates/local.erb', "---\ntype: local-template\n---\n")
      local_config = { 'other_key' => 'local-value' }
      File.write('.zh/config.yaml', local_config.to_yaml)
      config = Config.load
      assert_equal File.realpath(@temp_dir), File.realpath(config['notebook_path'])
      types = Config.template_types(config)
      assert_includes types, 'global-template'
      assert_includes types, 'local-template'
      assert_equal 'local-value', config['other_key']
    end
  end

  def test_load_finds_config_via_cwd
    Dir.chdir(@temp_dir) do
      FileUtils.mkdir_p('.zh')
      local_config = {}
      File.write('.zh/config.yaml', local_config.to_yaml)
      config = Config.load
      assert_equal File.realpath(@temp_dir), File.realpath(config['notebook_path'])
      assert_includes Config.template_types(config), 'note'
    end
  end

  def test_load_finds_config_via_directory_walk
    notebook_dir = File.join(@temp_home, 'notebook')
    FileUtils.mkdir_p(File.join(notebook_dir, '.zh'))
    File.write(File.join(notebook_dir, '.zh', 'config.yaml'), {}.to_yaml)
    subdir = File.join(notebook_dir, 'subdir', 'deep')
    FileUtils.mkdir_p(subdir)
    Dir.chdir(subdir) do
      config = Config.load
      assert_equal File.realpath(notebook_dir), File.realpath(config['notebook_path'])
      assert Config.template_types(config).length >= 1
    end
  end

  def test_load_finds_config_via_env_var
    notebook_dir = File.join(@temp_home, 'notebook')
    FileUtils.mkdir_p(File.join(notebook_dir, '.zh'))
    File.write(File.join(notebook_dir, '.zh', 'config.yaml'), {}.to_yaml)
    ENV['ZH_NOTEBOOK_PATH'] = notebook_dir
    Dir.chdir(@temp_dir) do
      config = Config.load
      assert_equal File.realpath(notebook_dir), File.realpath(config['notebook_path'])
      assert Config.template_types(config).length >= 1
    end
  ensure
    ENV.delete('ZH_NOTEBOOK_PATH')
  end

  def test_load_merges_local_with_global_when_found_via_cwd
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    FileUtils.mkdir_p(File.join(config_dir, 'templates'))
    File.write(File.join(config_dir, 'templates', 'global.erb'), "---\ntype: global-template\n---\n")
    global_config = { 'notebook_path' => @temp_dir, 'global_key' => 'global-value' }
    File.write(@global_config_file, global_config.to_yaml)
    Dir.chdir(@temp_dir) do
      FileUtils.mkdir_p('.zh/templates')
      File.write('.zh/templates/local.erb', "---\ntype: local-template\n---\n")
      local_config = { 'local_key' => 'local-value' }
      File.write('.zh/config.yaml', local_config.to_yaml)
      config = Config.load
      assert_equal File.realpath(@temp_dir), File.realpath(config['notebook_path'])
      types = Config.template_types(config)
      assert_includes types, 'global-template'
      assert_includes types, 'local-template'
      assert_equal 'global-value', config['global_key']
      assert_equal 'local-value', config['local_key']
    end
  end

  def test_load_merged_templates_include_global_only_types
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    global_tpl = File.join(config_dir, 'templates')
    FileUtils.mkdir_p(global_tpl)
    File.write(File.join(global_tpl, 'journal.erb'), "---\ntype: journal\n---\n")
    File.write(File.join(global_tpl, 'meeting.erb'), "---\ntype: meeting\n---\n")
    File.write(File.join(global_tpl, 'note.erb'), "---\ntype: note\n---\n")
    global_config = { 'notebook_path' => @temp_dir }
    File.write(@global_config_file, global_config.to_yaml)
    Dir.chdir(@temp_dir) do
      FileUtils.mkdir_p('.zh')
      FileUtils.mkdir_p('.zh/templates')
      File.write('.zh/templates/note.erb', "---\ntype: note\n---\n")
      File.write('.zh/config.yaml', {}.to_yaml)
      config = Config.load
      assert_equal File.realpath(@temp_dir), File.realpath(config['notebook_path'])
      types = Config.template_types(config)
      assert_includes types, 'journal'
      assert_includes types, 'meeting'
      assert_includes types, 'note'
      journal_template = Config.get_template(config, 'journal')
      assert journal_template, 'journal template should be found via discovery'
      assert_equal 'journal', journal_template['type']
      assert_equal 'journal.erb', journal_template['template_file']
    end
  end

  def test_load_merged_templates_local_overrides_global_for_same_type
    config_dir = File.join(@temp_home, '.config', 'zh')
    FileUtils.mkdir_p(config_dir)
    global_tpl = File.join(config_dir, 'templates')
    FileUtils.mkdir_p(global_tpl)
    File.write(File.join(global_tpl, 'note.erb'), "---\ntype: note\n---\n")
    global_config = { 'notebook_path' => @temp_dir }
    File.write(@global_config_file, global_config.to_yaml)
    Dir.chdir(@temp_dir) do
      FileUtils.mkdir_p('.zh/templates')
      File.write('.zh/templates/note.erb', "---\ntype: note\n---\n")
      File.write('.zh/config.yaml', {}.to_yaml)
      config = Config.load
      assert_equal File.realpath(@temp_dir), File.realpath(config['notebook_path'])
      note_template = Config.get_template(config, 'note')
      assert note_template, 'note template should be found'
      assert_equal 'note', note_template['type']
      assert_equal 'note.erb', note_template['template_file']
      resolved = Utils.find_template_file(config['notebook_path'], 'note.erb')
      assert resolved, 'template file should resolve'
      assert resolved.include?('.zh/templates'), 'local template should override (path contains .zh/templates)'
    end
  end

  def test_load_stops_walk_at_home_directory
    FileUtils.mkdir_p(File.join(@temp_home, '.zh', 'templates'))
    File.write(File.join(@temp_home, '.zh', 'templates', 'home.erb'), "---\ntype: home-template\n---\n")
    File.write(File.join(@temp_home, '.zh', 'config.yaml'), {}.to_yaml)
    subdir = File.join(@temp_home, 'subdir', 'deep')
    FileUtils.mkdir_p(subdir)
    Dir.chdir(subdir) do
      config = Config.load
      assert_equal File.realpath(@temp_home), File.realpath(config['notebook_path'])
      assert_includes Config.template_types(config), 'home-template'
    end
  end

  def test_find_zh_directory_walks_up_tree
    notebook_dir = File.join(@temp_home, 'notebook')
    FileUtils.mkdir_p(File.join(notebook_dir, '.zh'))
    
    subdir = File.join(notebook_dir, 'subdir', 'deep', 'nested')
    FileUtils.mkdir_p(subdir)
    
    found = Config.find_zh_directory(subdir)
    assert_equal File.join(notebook_dir, '.zh'), found
  end

  def test_find_zh_directory_returns_nil_when_not_found
    subdir = File.join(@temp_dir, 'subdir', 'deep')
    FileUtils.mkdir_p(subdir)
    
    found = Config.find_zh_directory(subdir)
    assert_nil found
  end

  def test_find_zh_directory_stops_at_home
    # Create .zh in a directory that would be above home if we kept walking
    # But we should stop at home
    FileUtils.mkdir_p(File.join(@temp_home, '.zh'))
    
    # Start from a subdirectory
    subdir = File.join(@temp_home, 'subdir')
    FileUtils.mkdir_p(subdir)
    
    found = Config.find_zh_directory(subdir)
    # Should find .zh in home
    assert_equal File.join(@temp_home, '.zh'), found
  end

  def test_default_engine_date_format
    assert_equal '%Y-%m-%d', Config.default_engine_date_format
  end

  def test_default_engine_slugify_replacement
    assert_equal '-', Config.default_engine_slugify_replacement
  end

  def test_get_engine_date_format_with_config
    config = { 'engine' => { 'date_format' => '%m/%d/%Y' } }
    assert_equal '%m/%d/%Y', Config.get_engine_date_format(config)
  end

  def test_get_engine_date_format_without_config
    config = {}
    assert_equal Config.default_engine_date_format, Config.get_engine_date_format(config)
  end

  def test_get_engine_slugify_replacement_with_config
    config = { 'engine' => { 'slugify_replacement' => '_' } }
    assert_equal '_', Config.get_engine_slugify_replacement(config)
  end

  def test_get_engine_slugify_replacement_without_config
    config = {}
    assert_equal Config.default_engine_slugify_replacement, Config.get_engine_slugify_replacement(config)
  end

  def test_get_engine_date_format_with_nil_config
    assert_equal Config.default_engine_date_format, Config.get_engine_date_format(nil)
  end

  def test_get_engine_slugify_replacement_with_nil_config
    assert_equal Config.default_engine_slugify_replacement, Config.get_engine_slugify_replacement(nil)
  end

  def test_default_engine_default_alias
    assert_equal '{type}> {date}: {title}', Config.default_engine_default_alias
  end

  def test_get_engine_default_alias_with_config
    config = { 'engine' => { 'default_alias' => '{type} - {title}' } }
    assert_equal '{type} - {title}', Config.get_engine_default_alias(config)
  end

  def test_get_engine_default_alias_without_config
    config = {}
    assert_equal Config.default_engine_default_alias, Config.get_engine_default_alias(config)
  end

  def test_get_engine_default_alias_with_nil_config
    assert_equal Config.default_engine_default_alias, Config.get_engine_default_alias(nil)
  end

  def test_get_journal_path_pattern_with_config
    config = { 'journal' => { 'path_pattern' => 'daily/{date}.md' } }
    assert_equal 'daily/{date}.md', Config.get_journal_path_pattern(config)
  end

  def test_get_journal_path_pattern_without_config
    config = {}
    assert_equal Config.default_journal_path_pattern, Config.get_journal_path_pattern(config)
  end

  def test_get_journal_path_pattern_with_nil_config
    assert_equal Config.default_journal_path_pattern, Config.get_journal_path_pattern(nil)
  end

  def test_default_journal_path_pattern
    assert_equal 'journal/{date}.md', Config.default_journal_path_pattern
  end

  def test_get_journal_default_title_with_config
    config = { 'journal' => { 'default_title' => 'Daily: {date}' } }
    assert_equal 'Daily: {date}', Config.get_journal_default_title(config)
  end

  def test_get_journal_default_title_without_config
    config = {}
    assert_equal Config.default_journal_default_title, Config.get_journal_default_title(config)
  end

  def test_get_journal_default_title_with_nil_config
    assert_equal Config.default_journal_default_title, Config.get_journal_default_title(nil)
  end

  def test_default_journal_default_title
    assert_equal 'Journal for {date}', Config.default_journal_default_title
  end

  def test_get_tool_command_returns_executable_only
    assert_equal 'rg', Config.get_tool_command({}, 'matcher')
    assert_equal 'fzf', Config.get_tool_command({}, 'filter')
    assert_equal 'glow', Config.get_tool_command({}, 'reader')
    assert_equal 'bat', Config.get_tool_command({}, 'preview')
  end

  def test_get_tool_command_with_config
    config = { 'tools' => { 'filter' => { 'command' => 'sk' }, 'matcher' => { 'command' => 'rg' } } }
    assert_equal 'sk', Config.get_tool_command(config, 'filter')
    assert_equal 'rg', Config.get_tool_command(config, 'matcher')
  end

  def test_get_tool_command_editor_prefers_env_over_config
    saved = ENV['EDITOR']
    config = { 'tools' => { 'editor' => { 'command' => 'vim' } } }
    begin
      ENV['EDITOR'] = 'nano'
      assert_equal 'nano', Config.get_tool_command(config, 'editor'),
                   'EDITOR set: should use ENV even when config has tools.editor.command'
      ENV.delete('EDITOR')
      assert_equal 'vim', Config.get_tool_command(config, 'editor'),
                   'EDITOR unset: should use config'
      assert_equal 'editor', Config.get_tool_command({}, 'editor'),
                   'Both unset: should fall back to editor'
      ENV['EDITOR'] = '  '
      assert_equal 'vim', Config.get_tool_command(config, 'editor'),
                   'EDITOR empty/whitespace: should use config'
    ensure
      if saved.nil?
        ENV.delete('EDITOR')
      else
        ENV['EDITOR'] = saved
      end
    end
  end

  def test_get_tool_module_args_with_config
    config = { 'tools' => { 'editor' => { 'find' => { 'args' => '{1} +{2}' } } } }
    assert_equal '{1} +{2}', Config.get_tool_module_args(config, 'editor', 'find')
  end

  def test_get_tool_module_args_defaults
    assert_equal '{1} +{2}', Config.get_tool_module_args({}, 'editor', 'find')
    assert_equal '{-1}', Config.get_tool_module_args({}, 'editor', 'search')
    assert_equal '{path}', Config.get_tool_module_args({}, 'editor', 'journal')
    assert_equal '', Config.get_tool_module_args({}, 'filter', 'find')
  end

  def test_get_tool_module_opts_with_config
    config = { 'tools' => { 'filter' => { 'find' => { 'opts' => ['--ansi'] } } } }
    assert_equal ['--ansi'], Config.get_tool_module_opts(config, 'filter', 'find')
  end

  def test_get_tool_module_opts_defaults
    assert_equal ['--ansi', '--disabled'], Config.get_tool_module_opts({}, 'filter', 'find')
    assert_equal ['--line-number', '--no-heading', '--color=always', '--smart-case'], Config.get_tool_module_opts({}, 'matcher', 'find')
    assert_equal [], Config.get_tool_module_opts({}, 'editor', 'find')
  end

  def test_default_tools_filter_search_display_format
    assert_equal '{1}>{3}>{4},{5} (id:{2}) [tags:{6}]', Config.default_tools_filter_search_display_format
  end

  def test_get_tools_filter_search_display_format_with_config
    config = { 'tools' => { 'filter' => { 'search' => { 'display_format' => '{5} - {2}' } } } }
    assert_equal '{5} - {2}', Config.get_tools_filter_search_display_format(config)
  end

  def test_get_tools_filter_search_display_format_without_config
    config = {}
    assert_equal Config.default_tools_filter_search_display_format, Config.get_tools_filter_search_display_format(config)
  end

  def test_get_tools_filter_search_display_format_with_nil_config
    assert_equal Config.default_tools_filter_search_display_format, Config.get_tools_filter_search_display_format(nil)
  end

  def test_default_tools_filter_select_expression
    assert_equal '-1', Config.default_tools_filter_select_expression
  end

  def test_get_tools_filter_search_select_expression_with_config
    config = { 'tools' => { 'filter' => { 'search' => { 'select_expression' => '2' } } } }
    assert_equal '2', Config.get_tools_filter_search_select_expression(config)
  end

  def test_get_tools_filter_search_select_expression_without_config
    config = {}
    assert_equal Config.default_tools_filter_select_expression, Config.get_tools_filter_search_select_expression(config)
  end

  def test_get_tools_filter_search_select_expression_with_nil_config
    assert_equal Config.default_tools_filter_select_expression, Config.get_tools_filter_search_select_expression(nil)
  end

  def test_default_tools_filter_preview_window
    assert_equal 'up:60%', Config.default_tools_filter_preview_window
  end

  def test_get_tools_filter_search_preview_window_with_config
    config = { 'tools' => { 'filter' => { 'preview_window' => 'right:70%,border-left' } } }
    assert_equal 'right:70%,border-left', Config.get_tools_filter_search_preview_window(config)
  end

  def test_get_tools_filter_search_preview_window_without_config
    assert_equal 'up:60%', Config.get_tools_filter_search_preview_window({})
    assert_equal 'up:60%', Config.get_tools_filter_search_preview_window(nil)
  end

  def test_default_tools_filter_search_header
    assert_equal 'Search: Enter=edit | Ctrl-r=read | Ctrl-o=open', Config.default_tools_filter_search_header
  end

  def test_get_tools_filter_header_with_config
    config = { 'tools' => { 'filter' => { 'header' => 'Enter=output | Ctrl-O=editor' } } }
    assert_equal 'Enter=output | Ctrl-O=editor', Config.get_tools_filter_header(config)
  end

  def test_get_tools_filter_search_header_with_config
    config = { 'tools' => { 'filter' => { 'search' => { 'header' => 'Search header' } } } }
    assert_equal 'Search header', Config.get_tools_filter_search_header(config)
  end

  def test_get_tools_filter_header_without_config
    assert_equal 'Search: Enter=edit | Ctrl-r=read | Ctrl-o=open', Config.get_tools_filter_header({})
    assert_equal 'Search: Enter=edit | Ctrl-r=read | Ctrl-o=open', Config.get_tools_filter_header(nil)
  end

  def test_default_tools_filter_find_header
    assert_equal 'Find: Enter=edit | Ctrl-r=read | Ctrl-o=open', Config.default_tools_filter_find_header
  end

  def test_get_tools_filter_find_header_with_config
    config = { 'tools' => { 'filter' => { 'find' => { 'header' => 'Find: custom header' } } } }
    assert_equal 'Find: custom header', Config.get_tools_filter_find_header(config)
  end

  def test_get_tools_filter_find_header_falls_back_to_search_header_then_default
    # Find header: find.header then search.header then default (per plan)
    config = { 'tools' => { 'filter' => { 'search' => { 'header' => 'Search header' } } } }
    assert_equal 'Search header', Config.get_tools_filter_find_header(config)
    config_none = { 'tools' => { 'filter' => { 'header' => 'Generic header' } } }
    assert_equal Config.default_tools_filter_find_header, Config.get_tools_filter_find_header(config_none)
  end

  def test_get_tools_filter_preview_window_search_and_find_override
    config = {
      'tools' => {
        'filter' => {
          'preview_window' => 'up:50%',
          'search' => { 'preview_window' => 'right:70%' }
        }
      }
    }
    assert_equal 'right:70%', Config.get_tools_filter_search_preview_window(config)
    assert_equal 'up:50%', Config.get_tools_filter_find_preview_window(config)
  end

  def test_get_search_limit_with_config
    config = { 'search' => { 'limit' => 50 } }
    assert_equal 50, Config.get_search_limit(config)
  end

  def test_default_find_glob_returns_array
    assert_equal ['*.md', '*.txt', '*.markdown'], Config.default_find_glob
  end

  def test_default_find_ignore_glob_returns_array
    assert_equal ['!.zh', '!.git', '!.DS_Store'], Config.default_find_ignore_glob
  end

  def test_get_find_glob_with_config_array
    config = { 'find' => { 'glob' => ['*.md', '*.txt'] } }
    assert_equal ['*.md', '*.txt'], Config.get_find_glob(config)
  end

  def test_get_find_glob_with_config_single_string_normalized_to_array
    config = { 'find' => { 'glob' => '*.md' } }
    assert_equal ['*.md'], Config.get_find_glob(config)
  end

  def test_get_find_glob_without_config_uses_default
    assert_equal Config.default_find_glob, Config.get_find_glob({})
    assert_equal Config.default_find_glob, Config.get_find_glob(nil)
  end

  def test_get_find_ignore_glob_with_config_array
    config = { 'find' => { 'ignore_glob' => ['!.zh', '!.git'] } }
    assert_equal ['!.zh', '!.git'], Config.get_find_ignore_glob(config)
  end

  def test_get_find_ignore_glob_with_config_single_string_normalized_to_array
    config = { 'find' => { 'ignore_glob' => '!.zh' } }
    assert_equal ['!.zh'], Config.get_find_ignore_glob(config)
  end

  def test_get_find_ignore_glob_without_config_uses_default
    assert_equal Config.default_find_ignore_glob, Config.get_find_ignore_glob({})
    assert_equal Config.default_find_ignore_glob, Config.get_find_ignore_glob(nil)
  end

  def test_get_import_default_target_dir_with_config
    config = { 'import' => { 'default_target_dir' => 'imported' } }
    assert_equal 'imported', Config.get_import_default_target_dir(config)
  end

  def test_get_import_default_target_dir_without_config
    assert_equal Config.default_import_target_dir, Config.get_import_default_target_dir({})
    assert_equal Config.default_import_target_dir, Config.get_import_default_target_dir(nil)
  end

  def test_default_import_target_dir
    assert_equal '.', Config.default_import_target_dir
  end

  def test_default_engine_db_result_delimiter
    assert_equal '|', Config.default_engine_db_result_delimiter
  end

  def test_get_engine_db_result_delimiter_with_config
    config = { 'engine' => { 'db_result_delimiter' => '\t' } }
    assert_equal '\t', Config.get_engine_db_result_delimiter(config)
  end

  def test_get_engine_db_result_delimiter_without_config
    assert_equal '|', Config.get_engine_db_result_delimiter({})
    assert_equal '|', Config.get_engine_db_result_delimiter(nil)
  end

  def test_get_find_reload_delay_with_config
    config = { 'find' => { 'reload_delay' => 0.2 } }
    assert_equal 0.2, Config.get_find_reload_delay(config)
  end

  def test_default_tools_filter_keybindings
    default = Config.default_tools_filter_keybindings
    assert_equal 3, default.size
    assert_includes default.join, 'editor_command'
    assert_includes default.join, 'reader_command'
    assert_includes default.join, 'open_command'
  end

  def test_get_tools_filter_keybindings_with_config
    config = { 'tools' => { 'filter' => { 'keybindings' => ['enter:execute({editor_command})', 'ctrl-o:execute({open_command})'] } } }
    assert_equal ['enter:execute({editor_command})', 'ctrl-o:execute({open_command})'], Config.get_tools_filter_keybindings(config)
  end

  def test_get_tools_filter_keybindings_without_config
    assert_equal Config.default_tools_filter_keybindings, Config.get_tools_filter_keybindings({})
    assert_equal Config.default_tools_filter_keybindings, Config.get_tools_filter_keybindings(nil)
  end

  def test_get_tools_filter_keybindings_normalizes_to_strings_and_rejects_empty
    config = { 'tools' => { 'filter' => { 'keybindings' => ['a', '', '  ', 'b'] } } }
    assert_equal ['a', 'b'], Config.get_tools_filter_keybindings(config)
  end

  def test_substitute_filter_keybinding_placeholders
    str = 'enter:execute({editor_command}),ctrl-r:execute({reader_command}),ctrl-o:execute({open_command})'
    result = Config.substitute_filter_keybinding_placeholders(
      str,
      editor_command: 'vim {path}',
      reader_command: 'glow {path}',
      open_command: 'open {path}'
    )
    assert_includes result, 'vim {path}'
    assert_includes result, 'glow {path}'
    assert_includes result, 'open {path}'
    refute_includes result, '{editor_command}'
    refute_includes result, '{reader_command}'
    refute_includes result, '{open_command}'
  end

  # --- Git Configuration Tests ---

  def test_default_git_auto_commit
    assert_equal false, Config.default_git_auto_commit
  end

  def test_get_git_auto_commit_with_config_true
    config = { 'git' => { 'auto_commit' => true } }
    assert_equal true, Config.get_git_auto_commit(config)
  end

  def test_get_git_auto_commit_with_config_false
    config = { 'git' => { 'auto_commit' => false } }
    assert_equal false, Config.get_git_auto_commit(config)
  end

  def test_get_git_auto_commit_without_config
    assert_equal false, Config.get_git_auto_commit({})
    assert_equal false, Config.get_git_auto_commit(nil)
  end

  def test_default_git_auto_push
    assert_equal false, Config.default_git_auto_push
  end

  def test_get_git_auto_push_with_config_true
    config = { 'git' => { 'auto_push' => true } }
    assert_equal true, Config.get_git_auto_push(config)
  end

  def test_get_git_auto_push_with_config_false
    config = { 'git' => { 'auto_push' => false } }
    assert_equal false, Config.get_git_auto_push(config)
  end

  def test_get_git_auto_push_without_config
    assert_equal false, Config.get_git_auto_push({})
    assert_equal false, Config.get_git_auto_push(nil)
  end

  def test_default_git_remote
    assert_equal 'origin', Config.default_git_remote
  end

  def test_get_git_remote_with_config
    config = { 'git' => { 'remote' => 'upstream' } }
    assert_equal 'upstream', Config.get_git_remote(config)
  end

  def test_get_git_remote_without_config
    assert_equal 'origin', Config.get_git_remote({})
    assert_equal 'origin', Config.get_git_remote(nil)
  end

  def test_default_git_branch
    assert_equal 'main', Config.default_git_branch
  end

  def test_get_git_branch_with_config
    config = { 'git' => { 'branch' => 'master' } }
    assert_equal 'master', Config.get_git_branch(config)
  end

  def test_get_git_branch_without_config
    assert_equal 'main', Config.get_git_branch({})
    assert_equal 'main', Config.get_git_branch(nil)
  end

  def test_default_git_commit_message_template
    assert_equal 'Update notes: {changed_count} file(s)', Config.default_git_commit_message_template
  end

  def test_get_git_commit_message_template_with_config
    config = { 'git' => { 'commit_message_template' => 'Notes: {changed_count} changes' } }
    assert_equal 'Notes: {changed_count} changes', Config.get_git_commit_message_template(config)
  end

  def test_get_git_commit_message_template_without_config
    assert_equal 'Update notes: {changed_count} file(s)', Config.get_git_commit_message_template({})
    assert_equal 'Update notes: {changed_count} file(s)', Config.get_git_commit_message_template(nil)
  end

  def test_default_git_history_limit
    assert_equal 20, Config.default_git_history_limit
  end

  def test_get_git_history_limit_with_config
    config = { 'git' => { 'history_limit' => 50 } }
    assert_equal 50, Config.get_git_history_limit(config)
  end

  def test_get_git_history_limit_without_config
    assert_equal 20, Config.get_git_history_limit({})
    assert_equal 20, Config.get_git_history_limit(nil)
  end

  def test_get_git_history_limit_with_invalid_value
    config = { 'git' => { 'history_limit' => -5 } }
    assert_equal 20, Config.get_git_history_limit(config)
  end
end
