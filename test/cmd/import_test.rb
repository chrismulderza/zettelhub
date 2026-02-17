# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'yaml'
require 'fileutils'
require 'pathname'
require 'sqlite3'
require_relative '../../lib/cmd/import'
require_relative '../../lib/cmd/init'
require_relative '../../lib/config'
require_relative '../../lib/indexer'
require_relative '../../lib/models/note'

class ImportCommandTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @temp_home = Dir.mktmpdir
    @sources_dir = Dir.mktmpdir
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
    global_config = { 'notebook_path' => @tmpdir }
    File.write(@global_config_file, global_config.to_yaml)

    Dir.chdir(@tmpdir) do
      InitCommand.new.run
    end

    @db_path = File.join(@tmpdir, '.zh', 'index.db')
  end

  def teardown
    Dir.singleton_class.class_eval do
      alias_method :home, :original_home
      remove_method :original_home
    end
    ENV['HOME'] = @original_home_env if @original_home_env
    FileUtils.remove_entry @tmpdir
    FileUtils.remove_entry @temp_home
    FileUtils.remove_entry @sources_dir
    Config.send(:remove_const, :CONFIG_FILE)
    Config.const_set(:CONFIG_FILE, @original_config_file)
  end

  def test_import_help
    cmd = ImportCommand.new
    out, = capture_io { cmd.run('--help') }
    assert_match(/Import markdown notes/, out)
    assert_match(/USAGE:/, out)
    assert_match(/--dry-run/, out)
    assert_match(/--into/, out)
    assert_match(/--recursive/, out)
  end

  def test_import_completion_options
    cmd = ImportCommand.new
    out, = capture_io { cmd.run('--completion', '--options') }
    opts = out.strip.split
    assert_includes opts, '--into'
    assert_includes opts, '--target-dir'
    assert_includes opts, '--recursive'
    assert_includes opts, '--dry-run'
    assert_includes opts, '--help'
  end

  def test_import_completion_into_option
    cmd = ImportCommand.new
    out, = capture_io { cmd.run('--completion', '--into') }
    assert_equal '__DIR__', out.strip, 'Completion for --into should return __DIR__ signal'
  end

  def test_import_completion_target_dir_option
    cmd = ImportCommand.new
    out, = capture_io { cmd.run('--completion', '--target-dir') }
    assert_equal '__DIR__', out.strip, 'Completion for --target-dir should return __DIR__ signal'
  end

  def test_import_assigns_new_id_and_updates_frontmatter
    note_a = <<~MD
      ---
      id: oldid1234
      type: note
      title: Note A
      ---
      # Note A
      Body
    MD
    File.write(File.join(@sources_dir, 'a.md'), note_a)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'imported', File.join(@sources_dir, 'a.md')) }
    end

    imported = Dir.glob(File.join(@tmpdir, 'imported', '*.md'))
    assert_equal 1, imported.size, 'Exactly one file under imported/'
    content = File.read(imported.first)
    assert content.start_with?('---'), 'Has front matter'
    metadata, = parse_front_matter(content)
    refute_equal 'oldid1234', metadata['id'], 'ID was changed'
    assert_match(/\A[a-f0-9]{8}\z/, metadata['id'], 'New ID is 8-char hex')
    assert_equal 'Note A', metadata['title']
  end

  def test_import_target_directory
    note = <<~MD
      ---
      id: x1
      title: One
      ---
      Body
    MD
    File.write(File.join(@sources_dir, 'one.md'), note)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'subdir', File.join(@sources_dir, 'one.md')) }
    end

    files = Dir.glob(File.join(@tmpdir, 'subdir', '*.md'))
    assert_equal 1, files.size
    assert File.exist?(files.first)
  end

  def test_import_resolves_wikilinks
    note_b = <<~MD
      ---
      id: b0000001
      title: Note B
      ---
      # Note B
      See [[Note A]] and [[a0000001]].
    MD
    note_a = <<~MD
      ---
      id: a0000001
      title: Note A
      ---
      # Note A
      Link to [[Note B]].
    MD
    File.write(File.join(@sources_dir, 'b.md'), note_b)
    File.write(File.join(@sources_dir, 'a.md'), note_a)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'imp', File.join(@sources_dir, 'a.md'), File.join(@sources_dir, 'b.md')) }
    end

    files = Dir.glob(File.join(@tmpdir, 'imp', '*.md'))
    assert_equal 2, files.size
    ids = files.map { |f| parse_front_matter(File.read(f))[0]['id'] }.sort
    assert_equal 2, ids.uniq.size, 'Two distinct IDs'

    # One of the files should have had [[Note B]] and [[a0000001]] replaced with the new ID for note B / note A
    contents = files.map { |f| File.read(f) }
    # Each body should contain [[...]] with an 8-char hex (the new ID), not the old id or title
    contents.each do |c|
      body = c.split('---', 3)[2].to_s
      body.scan(/\[\[([^\]]+)\]\]/).each do |(inner)|
        assert_match(/\A[a-f0-9]{8}\z/, inner.strip, "Wikilink should be resolved to new ID, got [[#{inner}]]")
      end
    end
  end

  def test_import_resolves_markdown_links
    note_a = <<~MD
      ---
      id: a1
      title: A
      ---
      [see B](b.md)
    MD
    note_b = <<~MD
      ---
      id: b2
      title: B
      ---
      Back to [A](a.md)
    MD
    File.write(File.join(@sources_dir, 'a.md'), note_a)
    File.write(File.join(@sources_dir, 'b.md'), note_b)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'links', File.join(@sources_dir, 'a.md'), File.join(@sources_dir, 'b.md')) }
    end

    files = Dir.glob(File.join(@tmpdir, 'links', '*.md')).sort_by { |f| File.basename(f) }
    assert_equal 2, files.size
    # Each file should have a link like [text](links/xxxxxxxx-title.md) (new path under notebook)
    contents = files.map { |f| File.read(f) }
    assert contents.any? { |c| c.include?('](links/') }, 'At least one link should point to links/...'
  end

  def test_import_indexes_notes
    note = <<~MD
      ---
      id: idx1
      title: Indexed Note
      ---
      Content
    MD
    File.write(File.join(@sources_dir, 'idx.md'), note)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'imp', File.join(@sources_dir, 'idx.md')) }
    end

    db = SQLite3::Database.new(@db_path)
    rel_path = Dir.glob(File.join(@tmpdir, 'imp', '*.md')).first
    rel_path = Pathname.new(rel_path).relative_path_from(Pathname.new(@tmpdir)).to_s
    row = db.execute('SELECT id, path FROM notes WHERE path = ?', [rel_path]).first
    db.close
    assert row, "Imported note should be in index with path #{rel_path}"
    assert_match(/\A[a-f0-9]{8}\z/, row[0])
  end

  def test_dry_run_writes_no_files
    File.write(File.join(@sources_dir, 'x.md'), "---\nid: x\ntitle: X\n---\nBody")

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--dry-run', '--into', 'dry', File.join(@sources_dir, 'x.md')) }
    end

    refute File.exist?(File.join(@tmpdir, 'dry')), 'Dry run must not create target dir'
    refute File.directory?(File.join(@tmpdir, 'dry'))
  end

  def test_dry_run_reports_would_import_and_changes
    note = <<~MD
      ---
      id: oldid99
      title: Dry Note
      ---
      See [[oldid99]].
    MD
    File.write(File.join(@sources_dir, 'dry.md'), note)

    out, = Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--dry-run', '--into', 'imp', File.join(@sources_dir, 'dry.md')) }
    end

    assert_match(/Would import \(1\)/, out)
    assert_match(/dry\.md/, out)
    assert_match(/id: oldid99 ->/, out)
    assert_match(/wikilink \[\[oldid99\]\] ->/, out)
  end

  def test_dry_run_reports_failures
    # Use a file that exists but has invalid YAML so it is in the batch and fails during parse
    bad_file = File.join(@sources_dir, 'bad.md')
    File.write(bad_file, <<~MD)
      ---
      id: x
      title: Bad
      invalid: [unclosed
      ---
      Body
    MD

    out, = Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--dry-run', '--into', 'imp', bad_file) }
    end

    assert_match(/Would fail/, out)
    assert_match(/bad\.md/, out)
  end

  def test_import_recursive_collects_nested_md
    FileUtils.mkdir_p(File.join(@sources_dir, 'nested'))
    note = <<~MD
      ---
      id: n1
      title: Nested
      ---
      Body
    MD
    File.write(File.join(@sources_dir, 'nested', 'n.md'), note)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'rec', '--recursive', @sources_dir) }
    end

    files = Dir.glob(File.join(@tmpdir, 'rec', '*.md'))
    assert_equal 1, files.size, 'Recursive import should include nested/n.md'
  end

  def test_import_type_aware_path
    note = <<~MD
      ---
      id: j1
      type: journal
      date: "2026-02-06"
      title: My Journal
      ---
      Body
    MD
    File.write(File.join(@sources_dir, 'j.md'), note)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'imp', File.join(@sources_dir, 'j.md')) }
    end

    expected = File.join(@tmpdir, 'imp', 'journal', '2026-02-06.md')
    assert File.exist?(expected), "Type-aware import should create #{expected}"
    content = File.read(expected)
    meta, = parse_front_matter(content)
    assert_equal 'My Journal', meta['title']
    assert_match(/\A[a-f0-9]{8}\z/, meta['id'])
  end

  def test_import_type_aware_default_tags
    note = <<~MD
      ---
      id: j2
      type: journal
      date: "2026-02-06"
      title: Daily
      tags: [existing]
      ---
      Body
    MD
    File.write(File.join(@sources_dir, 'daily.md'), note)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'imp', File.join(@sources_dir, 'daily.md')) }
    end

    path = File.join(@tmpdir, 'imp', 'journal', '2026-02-06.md')
    assert File.exist?(path), "Expected #{path}"
    content = File.read(path)
    meta, = parse_front_matter(content)
    tags = meta['tags']
    assert tags.is_a?(Array), 'tags should be array'
    assert_includes tags, 'journal', 'Template default_tags should include journal'
    assert_includes tags, 'daily', 'Template default_tags should include daily'
    assert_includes tags, 'existing', 'Existing tag should be preserved'
  end

  def test_import_type_aware_path_uses_source_date
    # Path should use source file date (2025-10-16), not system date (e.g. 2026/02).
    note = <<~MD
      ---
      id: m1
      type: meeting
      date: "2025-10-16"
      title: Discovery Ltd RHBK Keycloak
      ---
      Body
    MD
    File.write(File.join(@sources_dir, 'meeting.md'), note)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'imp', File.join(@sources_dir, 'meeting.md')) }
    end

    # Meeting template path is meetings/<year>/<month>/<id>-<slug>.md
    expected_dir = File.join(@tmpdir, 'imp', 'meetings', '2025', '10')
    assert Dir.exist?(expected_dir), "Import should place file under source date 2025/10, not system date: #{expected_dir}"
    files = Dir.glob(File.join(expected_dir, '*.md'))
    assert_equal 1, files.size, "Exactly one meeting file under 2025/10"
    content = File.read(files.first)
    meta, = parse_front_matter(content)
    assert_equal 'Discovery Ltd RHBK Keycloak', meta['title']
    assert_match(/\A[a-f0-9]{8}\z/, meta['id'])
  end

  def test_import_no_type_uses_fallback_path
    note = <<~MD
      ---
      id: n1
      title: No Type Note
      ---
      Body
    MD
    File.write(File.join(@sources_dir, 'n.md'), note)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'imp', File.join(@sources_dir, 'n.md')) }
    end

    files = Dir.glob(File.join(@tmpdir, 'imp', '*.md'))
    assert_equal 1, files.size
    basename = File.basename(files[0])
    assert_match(/\A[a-f0-9]{8}-no-type-note\.md\z/, basename, 'Fallback path should be new_id-slug.md')
  end

  def test_import_unknown_type_uses_fallback
    note = <<~MD
      ---
      id: u1
      type: unknown
      title: Unknown Type
      ---
      Body
    MD
    File.write(File.join(@sources_dir, 'u.md'), note)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'imp', File.join(@sources_dir, 'u.md')) }
    end

    files = Dir.glob(File.join(@tmpdir, 'imp', '*.md'))
    assert_equal 1, files.size
    basename = File.basename(files[0])
    assert_match(/\A[a-f0-9]{8}-unknown-type\.md\z/, basename, 'Unknown type should use fallback path')
  end

  def test_import_preserves_template_user_defined_front_matter_keys
    # Template with user-defined key (crm) is merged into output when type matches
    zk_templates = File.join(@tmpdir, '.zh', 'templates')
    FileUtils.mkdir_p(zk_templates)
    account_erb = <<~ERB
      ---
      id: "<%= id %>"
      type: account
      date: "<%= date %>"
      title: "<%= title %>"
      tags: <%= tags %>
      crm:
        id:
        owner:
        segment:
      config:
        path: "accounts/<%= id %>-<%= title %>.md"
      ---
      # <%= title %>
      <%= content %>
    ERB
    File.write(File.join(zk_templates, 'account.erb'), account_erb)

    source_note = <<~MD
      ---
      id: src1
      type: account
      title: Acme Corp
      ---
      Body
    MD
    File.write(File.join(@sources_dir, 'acme.md'), source_note)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'imp', File.join(@sources_dir, 'acme.md')) }
    end

    imported = Dir.glob(File.join(@tmpdir, 'imp', 'accounts', '*.md'))
    assert_equal 1, imported.size, 'Exactly one file under imp/accounts/'
    content = File.read(imported.first)
    meta, = parse_front_matter(content)
    assert meta.key?('crm'), 'Template user-defined key crm should appear in imported note'
    assert meta['crm'].is_a?(Hash), 'crm should be a hash'
    assert meta['crm'].key?('id'), 'crm should have id from template'
    assert meta['crm'].key?('owner'), 'crm should have owner from template'
    assert meta['crm'].key?('segment'), 'crm should have segment from template'
    assert_equal 'Acme Corp', meta['title'], 'Source title should be preserved'
    assert_match(/\A[a-f0-9]{8}\z/, meta['id'], 'New ID should be assigned')
  end

  def test_import_no_paths_exits_with_error
    Dir.chdir(@tmpdir) do
      pid = fork do
        ImportCommand.new.run('--into', 'imp')
      end
      Process.wait(pid)
      assert_equal 1, $?.exitstatus, 'Import with no paths should exit with 1'
    end
  end

  def test_import_markdown_link_case_and_extension_fallback
    note_a = <<~MD
      ---
      id: a1
      title: A
      ---
      Body A
    MD
    note_b = <<~MD
      ---
      id: b2
      title: B
      ---
      Link with wrong case [A](A.md) and no extension [A](a).
    MD
    File.write(File.join(@sources_dir, 'a.md'), note_a)
    File.write(File.join(@sources_dir, 'b.md'), note_b)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'links', File.join(@sources_dir, 'a.md'), File.join(@sources_dir, 'b.md')) }
    end

    files = Dir.glob(File.join(@tmpdir, 'links', '*.md'))
    assert_equal 2, files.size
    contents = files.map { |f| File.read(f) }
    # Both A.md and a should resolve to the new path of a.md (links/xxxxxxxx-a.md)
    contents.each do |c|
      next unless c.include?('Link with wrong case')
      assert_match(%r{\[A\]\(links/[a-f0-9]{8}-a\.md\)}, c, 'Case variant [A](A.md) should resolve to new path')
      assert_match(%r{\[A\]\(links/[a-f0-9]{8}-a\.md\)}, c, 'Extension-less [A](a) should resolve to new path')
    end
  end

  def test_import_markdown_link_duplicate_basenames_disambiguate_by_directory
    FileUtils.mkdir_p(File.join(@sources_dir, 'x'))
    FileUtils.mkdir_p(File.join(@sources_dir, 'y'))
    note_x = <<~MD
      ---
      id: x1
      title: From X
      ---
      In x. Link to [same](a.md).
    MD
    note_y = <<~MD
      ---
      id: y1
      title: From Y
      ---
      In y. Link to [same](a.md).
    MD
    note_ax = <<~MD
      ---
      id: ax1
      title: A in X
      ---
      I am x/a.md
    MD
    note_ay = <<~MD
      ---
      id: ay1
      title: A in Y
      ---
      I am y/a.md
    MD
    File.write(File.join(@sources_dir, 'x', 'a.md'), note_ax)
    File.write(File.join(@sources_dir, 'y', 'a.md'), note_ay)
    File.write(File.join(@sources_dir, 'x', 'x.md'), note_x)
    File.write(File.join(@sources_dir, 'y', 'y.md'), note_y)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'imp', '--recursive', @sources_dir) }
    end

    # Find the two notes that have "Link to [same](a.md)" - one from x, one from y
    files = Dir.glob(File.join(@tmpdir, 'imp', '**', '*.md'))
    from_x = files.find { |f| File.read(f).include?('In x.') }
    from_y = files.find { |f| File.read(f).include?('In y.') }
    assert from_x, 'Expected note from x'
    assert from_y, 'Expected note from y'
    # Each should resolve a.md to their same-directory source: x's note links to x/a's new path, y's to y/a's new path
    # New paths are under imp/ so we get imp/xxxxxxxx-from-x.md, imp/xxxxxxxx-from-y.md, imp/xxxxxxxx-a-in-x.md, imp/xxxxxxxx-a-in-y.md (flat with -r from two dirs)
    # Actually with --recursive we have x/a.md, x/x.md, y/a.md, y/y.md - all in one flat list? No, Dir.glob with ** gives full paths. So we have 4 files in imp/ with different basenames. So x.md content: link to a.md. When resolving from current_dir = x, resolved_abs = x/a.md. So we need the candidate for a.md that has source_abs = x/a.md. So we get the new path for x/a.md. Similarly for y. So the test is: from_x body should contain a link to the new_id of note_ax (x/a.md), and from_y to note_ay (y/a.md). We can't easily get the new_id without reading the imported file for a-in-x and a-in-y. We can assert that the link in from_x is different from the link in from_y (they point to different files).
    link_in_x = File.read(from_x).match(/\[same\]\((.*?)\)/)[1]
    link_in_y = File.read(from_y).match(/\[same\]\((.*?)\)/)[1]
    refute_equal link_in_x, link_in_y, 'Links from x and y should resolve to different targets (disambiguation by directory)'
    assert_match(%r{^imp/[a-f0-9]{8}-}, link_in_x, 'Link should be under imp/')
    assert_match(%r{^imp/[a-f0-9]{8}-}, link_in_y, 'Link should be under imp/')
  end

  def test_import_wikilink_case_insensitive_title
    note_a = <<~MD
      ---
      id: a1
      title: My Note
      ---
      Body A
    MD
    note_b = <<~MD
      ---
      id: b2
      title: Other
      ---
      See [[my note]] and [[MY NOTE]].
    MD
    File.write(File.join(@sources_dir, 'a.md'), note_a)
    File.write(File.join(@sources_dir, 'b.md'), note_b)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'imp', File.join(@sources_dir, 'a.md'), File.join(@sources_dir, 'b.md')) }
    end

    files = Dir.glob(File.join(@tmpdir, 'imp', '*.md'))
    note_my_note = files.find { |f| parse_front_matter(File.read(f))[0]['title'] == 'My Note' }
    note_other = files.find { |f| parse_front_matter(File.read(f))[0]['title'] == 'Other' }
    assert note_my_note && note_other
    new_id_a = parse_front_matter(File.read(note_my_note))[0]['id']
    content_other = File.read(note_other)
    # CommonMarker may escape [[ ]] in output; either way the resolved ID should appear (twice: [[my note]] and [[MY NOTE]] both -> same id)
    assert content_other.include?(new_id_a), "Resolved wikilinks should contain My Note's new ID #{new_id_a}"
    id_count = content_other.scan(Regexp.escape(new_id_a)).size
    assert id_count >= 2, "Both [[my note]] and [[MY NOTE]] should resolve to same ID (found #{id_count} occurrences)"
  end

  def test_import_wikilink_alias_resolution
    note_a = <<~MD
      ---
      id: a1
      title: Long Title Here
      aliases:
        - Short Name
      ---
      Body A
    MD
    note_b = <<~MD
      ---
      id: b2
      title: Other
      ---
      See [[Short Name]].
    MD
    File.write(File.join(@sources_dir, 'a.md'), note_a)
    File.write(File.join(@sources_dir, 'b.md'), note_b)

    Dir.chdir(@tmpdir) do
      capture_io { ImportCommand.new.run('--into', 'imp', File.join(@sources_dir, 'a.md'), File.join(@sources_dir, 'b.md')) }
    end

    files = Dir.glob(File.join(@tmpdir, 'imp', '*.md'))
    note_a_imported = files.find { |f| parse_front_matter(File.read(f))[0]['title'] == 'Long Title Here' }
    note_b_imported = files.find { |f| parse_front_matter(File.read(f))[0]['title'] == 'Other' }
    assert note_a_imported, 'Expected note A (Long Title Here)'
    assert note_b_imported, 'Expected note B (Other)'
    new_id_a = parse_front_matter(File.read(note_a_imported))[0]['id']
    content_b = File.read(note_b_imported)
    # CommonMarker may escape [[ ]] in output; body should contain the resolved ID
    assert content_b.include?(new_id_a), "Wikilink [[Short Name]] should resolve to note A's new ID #{new_id_a}"
  end

  private

  def parse_front_matter(content)
    return [{}, content] unless content.start_with?('---')
    parts = content.split('---', 3)
    return [{}, content] if parts.size < 3
    metadata = YAML.safe_load(parts[1]) || {}
    [metadata, parts[2].to_s]
  end

  def capture_io
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
