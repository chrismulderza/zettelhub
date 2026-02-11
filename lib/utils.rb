# frozen_string_literal: true

require 'yaml'
require 'date'
require 'securerandom'
require 'sqlite3'
require 'pathname'
require 'commonmarker'
require_relative 'config'

# Shared utilities: link extraction and resolution, front matter parsing, path/template helpers, and shell command checks.
module Utils
  # Link patterns shared by import, indexer, and link commands.
  WIKILINK_PATTERN = /\[\[([^\]]+)\]\]/.freeze
  # Match [text](url) - capture link text and url; url is non-greedy up to ) or end
  MARKDOWN_LINK_PATTERN = /\[([^\]]*)\]\(([^)]*)\)/.freeze

  # Returns array of unique wikilink target strings (inner of [[...]]) from body.
  def self.extract_wikilinks(body)
    return [] if body.to_s.empty?
    body.to_s.scan(WIKILINK_PATTERN).map { |m| m[0].to_s.strip }.reject(&:empty?).uniq
  end

  # Returns array of unique relative URLs from markdown links in body. Skips external (scheme) and anchor-only (#...) links.
  def self.extract_markdown_link_urls(body)
    return [] if body.to_s.empty?
    urls = []
    body.to_s.scan(MARKDOWN_LINK_PATTERN) do
      url = Regexp.last_match(2).to_s.strip
      next if url.empty? || url.start_with?('#')
      next if url.include?(':') && url =~ /\A[a-z][a-z0-9+.-]*:/i
      urls << url
    end
    urls.uniq
  end

  # Resolves a wikilink target (id, title, or alias) to a note id using the index db. Returns note_id or nil.
  def self.resolve_wikilink_to_id(link_text, db)
    return nil if link_text.to_s.strip.empty?
    inner = link_text.to_s.strip
    # By id (8-char hex)
    if inner =~ /\A[a-f0-9]{8}\z/i
      row = db.execute('SELECT id FROM notes WHERE id = ?', [inner]).first
      return row[0] if row
    end
    # By title (case-insensitive)
    row = db.execute('SELECT id FROM notes WHERE LOWER(TRIM(title)) = LOWER(?)', [inner]).first
    return row[0] if row
    # By alias (metadata.aliases can be string or array)
    db.execute('SELECT id, metadata FROM notes').each do |id, meta_json|
      next if meta_json.to_s.empty?
      meta = JSON.parse(meta_json) rescue {}
      aliases = meta['aliases']
      next if aliases.nil?
      aliases = [aliases] unless aliases.is_a?(Array)
      return id if aliases.any? { |a| a.to_s.strip.casecmp(inner) == 0 }
    end
    nil
  end

  # Resolves a relative markdown link URL to a note id. current_note_path and notebook_path are absolute paths; db is SQLite3::Database.
  # Returns note_id or nil. Normalizes .md and path separators for matching.
  # Tries current-note-relative resolution first; if no match and URL is safe for notebook-root, tries notebook-root-relative.
  def self.resolve_markdown_path_to_id(url, current_note_path, notebook_path, db)
    return nil if url.to_s.strip.empty?
    notebook_path = File.expand_path(notebook_path)
    current_dir = File.dirname(File.expand_path(current_note_path))
    resolved_abs = File.expand_path(url, current_dir)
    return nil unless resolved_abs.start_with?(notebook_path + File::SEPARATOR) || resolved_abs == notebook_path
    notebook_rel = Pathname.new(resolved_abs).relative_path_from(Pathname.new(notebook_path)).to_s
    notebook_rel_norm = notebook_rel.gsub(%r{/+}, '/').sub(/\.md\z/i, '')
    db.execute('SELECT id, path FROM notes').each do |id, path|
      path_norm = path.to_s.gsub(%r{/+}, '/').sub(/\.md\z/i, '')
      return id if path_norm.casecmp(notebook_rel_norm) == 0
      return id if File.expand_path(File.join(notebook_path, path)) == resolved_abs
    end
    # Fallback: try notebook-root-relative when URL is safe (no .., not absolute)
    url_str = url.to_s.strip
    safe_for_root = !url_str.include?('..') && !url_str.start_with?('/') && url_str !~ /\A[a-z][a-z0-9+.-]*:/i
    if safe_for_root
      resolved_abs = File.expand_path(url, notebook_path)
      return nil unless resolved_abs.start_with?(notebook_path + File::SEPARATOR) || resolved_abs == notebook_path
      notebook_rel = Pathname.new(resolved_abs).relative_path_from(Pathname.new(notebook_path)).to_s
      notebook_rel_norm = notebook_rel.gsub(%r{/+}, '/').sub(/\.md\z/i, '')
      db.execute('SELECT id, path FROM notes').each do |id, path|
        path_norm = path.to_s.gsub(%r{/+}, '/').sub(/\.md\z/i, '')
        return id if path_norm.casecmp(notebook_rel_norm) == 0
        return id if File.expand_path(File.join(notebook_path, path)) == resolved_abs
      end
    end
    nil
  end

  # Rewrites markdown links in body: any link whose resolved target equals old_rel_path (notebook-relative) is replaced with the relative URL to new_rel_path.
  # source_note_path is the absolute path of the note containing the link; notebook_path is the notebook root.
  def self.rewrite_markdown_links_for_rename(body, source_note_path, notebook_path, old_rel_path, new_rel_path)
    return body.to_s if body.to_s.empty?
    notebook_path = File.expand_path(notebook_path)
    source_dir = File.dirname(File.expand_path(source_note_path))
    old_rel_norm = old_rel_path.to_s.gsub(%r{/+}, '/').sub(/\.md\z/i, '')
    new_abs = File.join(notebook_path, new_rel_path.to_s)
    body.to_s.gsub(MARKDOWN_LINK_PATTERN) do
      link_text = Regexp.last_match(1)
      url = Regexp.last_match(2).to_s.strip
      if url.empty? || url.start_with?('#') || (url.include?(':') && url =~ /\A[a-z][a-z0-9+.-]*:/i)
        "[#{link_text}](#{url})"
      else
        resolved_abs = File.expand_path(url, source_dir)
        next "[#{link_text}](#{url})" unless resolved_abs.start_with?(notebook_path + File::SEPARATOR) || resolved_abs == notebook_path
        current_rel = Pathname.new(resolved_abs).relative_path_from(Pathname.new(notebook_path)).to_s
        current_rel_norm = current_rel.gsub(%r{/+}, '/').sub(/\.md\z/i, '')
        if current_rel_norm.casecmp(old_rel_norm) == 0
          new_rel_from_source = Pathname.new(new_abs).relative_path_from(Pathname.new(source_dir)).to_s
          "[#{link_text}](#{new_rel_from_source})"
        else
          "[#{link_text}](#{url})"
        end
      end
    end
  end

  # Resolves a single link URL to a new relative path using import-style maps. Used by import.
  # Returns [new_rel, method_symbol] or [nil, nil].
  def self.resolve_link_target_to_new_path(url, current_dir, source_abs_to_new_rel, source_basename_to_candidates)
    resolved_abs = File.expand_path(url, current_dir)
    new_rel = source_abs_to_new_rel[resolved_abs]
    return [new_rel, :exact_path] if new_rel

    link_basename = File.basename(url)
    cands = source_basename_to_candidates[link_basename]
    if cands.is_a?(Array) && cands.any?
      new_rel = disambiguate_basename_candidates(cands, resolved_abs, current_dir)
      return [new_rel, :basename] if new_rel
    end

    alt_basename = link_basename.end_with?('.md') ? link_basename.sub(/\.md\z/, '') : "#{link_basename}.md"
    cands = source_basename_to_candidates[alt_basename]
    if cands.is_a?(Array) && cands.any?
      new_rel = disambiguate_basename_candidates(cands, resolved_abs, current_dir)
      return [new_rel, :extension_fallback] if new_rel
    end

    source_basename_to_candidates.each do |bn, list|
      next unless bn.to_s.casecmp(link_basename.to_s) == 0 && list.is_a?(Array) && list.any?
      new_rel = disambiguate_basename_candidates(list, resolved_abs, current_dir)
      return [new_rel, :case_insensitive] if new_rel
    end

    [nil, nil]
  end

  # Picks best matching notebook-relative path from candidates (exact path, same dir, or first). Used by import.
  def self.disambiguate_basename_candidates(candidates, resolved_abs, current_dir)
    return candidates[0][1] if candidates.size == 1
    found = candidates.find { |src_abs, _| src_abs == resolved_abs }
    return found[1] if found
    same_dir = candidates.find { |src_abs, _| File.dirname(src_abs) == current_dir }
    return same_dir[1] if same_dir
    candidates[0][1]
  end

  # Rewrites markdown links in body using import-style path mapping. Used by import.
  def self.resolve_markdown_links_with_mapping(body, source_note_path, source_abs_to_new_rel, source_basename_to_candidates, debug: false)
    current_dir = File.dirname(File.expand_path(source_note_path))
    body.to_s.gsub(MARKDOWN_LINK_PATTERN) do
      link_text = Regexp.last_match(1)
      url = Regexp.last_match(2).to_s.strip
      if url.empty? || url.start_with?('#') || (url.include?(':') && url =~ /\A[a-z][a-z0-9+.-]*:/i)
        "[#{link_text}](#{url})"
      else
        new_rel, _method = resolve_link_target_to_new_path(url, current_dir, source_abs_to_new_rel, source_basename_to_candidates)
        if new_rel
          $stderr.puts("[DEBUG] resolved link (#{url}) -> (#{new_rel})") if debug
          "[#{link_text}](#{new_rel})"
        else
          $stderr.puts("[DEBUG] link (#{url}) not resolved (no match)") if debug
          "[#{link_text}](#{url})"
        end
      end
    end
  end

  # Parses CommonMark content and returns [metadata_hash, body_string]. Uses first ---...--- block as YAML.
  def self.parse_front_matter(content)
    doc = Commonmarker.parse(content, options: { extension: { front_matter_delimiter: '---' } })
    frontmatter_str = nil
    doc.walk do |node|
      if node.type == :frontmatter
        frontmatter_str = node.to_commonmark
        break
      end
    end
    metadata = if frontmatter_str
                 YAML.safe_load(frontmatter_str, permitted_classes: [Date]) || {}
               else
                 {}
               end
    # Keep content_without as original, just remove frontmatter block
    if content.start_with?('---')
      parts = content.split('---', 3)
      content_without = parts.size >= 3 ? parts[2] : content
    else
      content_without = content
    end
    [metadata, content_without]
  end

  # Returns a hash of time variables (date, year, month, week, etc.) for the current time. Used by templates.
  def self.current_time_vars(date_format: nil)
    now = Time.now
    format = date_format || Config.default_engine_date_format
    {
      'date' => now.strftime(format),
      'year' => now.strftime('%Y'),
      'month' => now.strftime('%m'),
      'week' => now.strftime('%V'),
      'week_year' => now.strftime('%G'),
      'month_name' => now.strftime('%B'),
      'month_name_short' => now.strftime('%b'),
      'day' => now.strftime('%d'),
      'day_name' => now.strftime('%A'),
      'day_name_short' => now.strftime('%a'),
      'time' => now.strftime('%H:%M'),
      'time_iso' => now.strftime('%H:%M:%S'),
      'hour' => now.strftime('%H'),
      'minute' => now.strftime('%M'),
      'second' => now.strftime('%S'),
      'timestamp' => now.strftime('%Y%m%d%H%M%S'),
      'id' => Utils.generate_id
    }
  end

  # Same structure as current_time_vars but for the given Date or Time (e.g. for journal by date).
  def self.time_vars_for_date(date, date_format: nil)
    t = date.is_a?(Time) ? date : date.to_time
    format = date_format || Config.default_engine_date_format
    {
      'date' => t.strftime(format),
      'year' => t.strftime('%Y'),
      'month' => t.strftime('%m'),
      'week' => t.strftime('%V'),
      'week_year' => t.strftime('%G'),
      'month_name' => t.strftime('%B'),
      'month_name_short' => t.strftime('%b'),
      'day' => t.strftime('%d'),
      'day_name' => t.strftime('%A'),
      'day_name_short' => t.strftime('%a'),
      'time' => t.strftime('%H:%M'),
      'time_iso' => t.strftime('%H:%M:%S'),
      'hour' => t.strftime('%H'),
      'minute' => t.strftime('%M'),
      'second' => t.strftime('%S'),
      'timestamp' => t.strftime('%Y%m%d%H%M%S'),
      'id' => Utils.generate_id
    }
  end

  # Replaces {key} in pattern with values from variables hash.
  def self.interpolate_pattern(pattern, variables)
    result = pattern.dup
    variables.each do |key, value|
      result.gsub!("{#{key}}", value.to_s)
    end
    result
  end

  # Recursively merges overlay into a copy of base. Overlay values win; for nested
  # hashes both must be hashes and are merged recursively. Used so template front
  # matter (base) provides structure and source metadata (overlay) overrides or fills in.
  def self.deep_merge(base, overlay)
    return base.dup if overlay.nil? || !overlay.is_a?(Hash)
    result = base.is_a?(Hash) ? base.dup : {}
    overlay.each do |key, overlay_val|
      base_val = result[key]
      result[key] = if base_val.is_a?(Hash) && overlay_val.is_a?(Hash)
                      deep_merge(base_val, overlay_val)
                    else
                      overlay_val
                    end
    end
    result
  end

  # Returns true if the given command is available in PATH (e.g. 'rg', 'fzf').
  def self.command_available?(cmd)
    system("which #{cmd} > /dev/null 2>&1")
  end

  # Exits with error message if command is not available.
  def self.require_command!(cmd, message)
    return if command_available?(cmd)

    $stderr.puts message
    exit 1
  end

  # Build a single shell command string from executable, option array, and args template.
  # Used by find and search to build editor/preview/reader/open invocations for fzf.
  def self.build_tool_invocation(executable, opts, args)
    cmd = [executable.to_s.strip, *opts, args.to_s.strip].reject(&:empty?).join(' ')
    $stderr.puts("[DEBUG] build_tool_invocation: #{cmd}") if ENV['ZH_DEBUG'] == '1'
    cmd
  end

  # Searches local, global, then bundled template dirs. Returns path or nil.
  def self.find_template_file(notebook_path, template_filename, debug: false)
    debug_print = ->(msg) { $stderr.puts("[DEBUG] #{msg}") if debug }

    local_file = File.join(Config.local_templates_dir(notebook_path), template_filename)
    debug_print.call("Local path: #{local_file}")
    if File.exist?(local_file)
      debug_print.call("Local template file found")
      return local_file
    end
    debug_print.call("Local template file not found")

    global_file = File.join(Config.global_templates_dir, template_filename)
    debug_print.call("Global path: #{global_file}")
    if File.exist?(global_file)
      debug_print.call("Global template file found")
      return global_file
    end
    debug_print.call("Global template file not found")

    bundled_file = File.join(Config.bundled_templates_dir, template_filename)
    debug_print.call("Bundled path: #{bundled_file}")
    if File.exist?(bundled_file)
      debug_print.call("Bundled template file found")
      return bundled_file
    end
    debug_print.call("Bundled template file not found")

    nil
  end

  # Like find_template_file but exits with message if not found. Used by add command.
  def self.find_template_file!(notebook_path, template_filename, debug: false)
    path = find_template_file(notebook_path, template_filename, debug: debug)
    return path if path

    local_file = File.join(Config.local_templates_dir(notebook_path), template_filename)
    global_file = File.join(Config.global_templates_dir, template_filename)
    bundled_file = File.join(Config.bundled_templates_dir, template_filename)
    puts "Template file not found: #{template_filename}"
    puts 'Searched locations:'
    puts "  #{local_file}"
    puts "  #{global_file}"
    puts "  #{bundled_file}"
    exit 1
  end

  # Default length of generated ID in characters (hex digits). Used by generate_id.
  ZK_DEFAULT_ID_LENGTH = 8

  # Returns an 8-character hex ID (SecureRandom).
  def self.generate_id
    SecureRandom.hex(ZK_DEFAULT_ID_LENGTH / 2)
  end

  # Returns the absolute path of the note file for the given note id, or nil if not found.
  # config must have 'notebook_path' set; uses Config.index_db_path to open the index.
  def self.note_path_by_id(config, id)
    notebook_path = config['notebook_path']
    return nil unless notebook_path && Dir.exist?(notebook_path)

    db_path = Config.index_db_path(notebook_path)
    return nil unless File.exist?(db_path)

    db = SQLite3::Database.new(db_path)
    row = db.execute('SELECT path FROM notes WHERE id = ?', [id.to_s.strip]).first
    db.close
    return nil unless row

    File.join(File.expand_path(notebook_path), row[0])
  end

  # Returns a single metadata attribute for a document by id, or nil if not found.
  # db_path: path to the index SQLite DB; document_id: note id; attribute_key: key in metadata JSON (e.g. 'uri').
  def self.get_metadata_attribute(db_path, document_id, attribute_key)
    return nil unless File.exist?(db_path.to_s)

    db = SQLite3::Database.new(db_path.to_s)
    row = db.execute('SELECT metadata FROM notes WHERE id = ?', [document_id.to_s.strip]).first
    db.close
    return nil unless row

    meta = JSON.parse(row[0] || '{}')
    key_s = attribute_key.to_s
    meta[key_s] || meta[attribute_key.to_sym]
  end

  # Rebuilds markdown with YAML front matter and validated body via CommonMarker.
  # Used when updating note front matter (e.g. tags) without changing the template.
  def self.reconstruct_note_content(metadata, body)
    front_matter_yaml = metadata.to_yaml.sub(/^---\n/, '')
    body_doc = Commonmarker.parse(body)
    validated_body = body_doc.to_commonmark
    markdown_string = "---\n#{front_matter_yaml}---\n\n#{validated_body}"
    final_doc = Commonmarker.parse(markdown_string, options: { extension: { front_matter_delimiter: '---' } })
    final_doc.to_commonmark
  end

  # Normalizes text to a slug: lowercased, non-alphanumeric replaced, collapsed/trimmed.
  def self.slugify(text, replacement_char: '-')
    return '' if text.nil? || text.to_s.empty?

    result = text.to_s.downcase
        .gsub(/[^a-z0-9\-_]/, replacement_char)  # Use replacement_char instead of underscore
        .gsub(/\s+/, replacement_char)            # Replace spaces with replacement_char
    
    # Handle empty replacement_char (remove characters)
    if replacement_char.empty?
      result = result.gsub(/[^a-z0-9]/, '')  # Remove all non-alphanumeric
    else
      # Escape the replacement character for use in regex
      escaped_char = Regexp.escape(replacement_char)
      result = result
          .gsub(/#{escaped_char}+/, replacement_char)  # Collapse multiple replacement chars
          .gsub(/^#{escaped_char}+|#{escaped_char}+$/, '')  # Remove leading/trailing replacement chars
    end
    
    result
  end
end
