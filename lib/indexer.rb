# frozen_string_literal: true

require 'sqlite3'
require 'json'
require 'pathname'
require 'fileutils'
require 'commonmarker'
require_relative 'config'
require_relative 'debug'
require_relative 'utils'

# Indexer for notes using SQLite with FTS5 full-text search and link tracking
class Indexer
  include Debug

  # Pattern to match #hashtags in body text (not inside code blocks).
  # Matches: #tag, #tag-name, #tag_name (1-50 chars, starts with letter).
  HASHTAG_PATTERN = /(?<![&\w])#([a-zA-Z][a-zA-Z0-9_-]{0,49})(?![a-zA-Z0-9_-])/.freeze

  # Sets db path from config, creates parent dir if needed.
  def initialize(config)
    @config = config
    @db_path = Config.index_db_path(@config['notebook_path'])
    @notebook_path = File.expand_path(@config['notebook_path'])
    @extract_body_hashtags = @config.dig('tags', 'extract_body_hashtags') != false
    FileUtils.mkdir_p(File.dirname(@db_path))
  end

  # Writes or updates note row, FTS row, links table, and backlinks section in note file.
  def index_note(note)
    debug_print("Indexing note: #{note.path} (id: #{note.id})")
    db = SQLite3::Database.new(@db_path)
    setup_schema(db)

    relative_path = Pathname.new(note.path).relative_path_from(Pathname.new(@notebook_path)).to_s
    filename = extract_filename(relative_path)
    title = note.title || ''
    body = note.body || ''
    description = note.metadata['description'].to_s
    full_text = [body, description].reject(&:empty?).join("\n")

    # Rename handling: if note exists with different path, rewrite markdown links in backlink sources
    existing_row = db.execute('SELECT id, path FROM notes WHERE id = ?', [note.id]).first
    if existing_row && existing_row[1] != relative_path
      old_rel_path = existing_row[1]
      new_rel_path = relative_path
      backlink_source_ids = db.execute('SELECT source_id FROM links WHERE target_id = ?', [note.id]).flatten
      debug_print("Rename detected: #{old_rel_path} -> #{new_rel_path}, updating #{backlink_source_ids.size} backlink source(s)")
      backlink_source_ids.each do |source_id|
        row = db.execute('SELECT path FROM notes WHERE id = ?', [source_id]).first
        next unless row
        source_path = File.join(@notebook_path, row[0])
        next unless File.exist?(source_path)
        begin
          content = File.read(source_path)
          metadata, old_body = Utils.parse_front_matter(content)
          new_body = Utils.rewrite_markdown_links_for_rename(old_body, source_path, @notebook_path, old_rel_path, new_rel_path)
          next if new_body == old_body
          File.write(source_path, Utils.reconstruct_note_content(metadata, new_body))
          debug_print("Updated backlink source: #{source_path}")
        rescue StandardError => e
          debug_print("Failed to update backlink source #{source_path}: #{e.message}")
        end
      end
    end

    # Old targets (for backlinks section refresh) before we delete this note's outgoing links
    old_targets = db.execute('SELECT target_id FROM links WHERE source_id = ?', [note.id]).flatten.uniq

    # Upsert note and FTS
    if existing_row.nil?
      debug_print("Insert new note: #{note.id}")
      db.execute(
        'INSERT INTO notes (id, path, metadata, title, body, filename) VALUES (?, ?, ?, ?, ?, ?)',
        [note.id, relative_path, note.metadata.to_json, title, body, filename]
      )
      db.execute('UPDATE notes_fts SET full_text = ? WHERE id = ?', [full_text, note.id])
    else
      debug_print("Update existing note: #{note.id}")
      db.execute('DELETE FROM notes_fts WHERE id = ?', [note.id])
      db.execute(
        'INSERT OR REPLACE INTO notes (id, path, metadata, title, body, filename) VALUES (?, ?, ?, ?, ?, ?)',
        [note.id, relative_path, note.metadata.to_json, title, body, filename]
      )
      db.execute('UPDATE notes_fts SET full_text = ? WHERE id = ?', [full_text, note.id])
    end

    # Links: delete outgoing from this note, then insert from body
    db.execute('DELETE FROM links WHERE source_id = ?', [note.id])
    new_targets = []
    body_with_desc = [body, description].reject(&:empty?).join("\n")
    wikilinks = Utils.extract_wikilinks(body_with_desc)
    md_urls = Utils.extract_markdown_link_urls(body_with_desc)
    debug_print("links: extracted #{wikilinks.size} wikilink target(s): #{wikilinks.size <= 5 ? wikilinks.inspect : wikilinks.first(5).inspect + ' ...'}")
    debug_print("links: extracted #{md_urls.size} markdown url(s): #{md_urls.size <= 5 ? md_urls.inspect : md_urls.first(5).inspect + ' ...'}")

    wikilink_inserts = 0
    wikilinks.each do |target|
      target_id = Utils.resolve_wikilink_to_id(target, db)
      if target_id
        db.execute('INSERT INTO links (source_id, target_id, link_type) VALUES (?, ?, ?)', [note.id, target_id, 'wikilink'])
        new_targets << target_id
        wikilink_inserts += 1
        debug_print("resolved wikilink [[#{target}]] -> #{target_id}")
      else
        debug_print("unresolved wikilink: #{target.inspect}")
      end
    end
    markdown_inserts = 0
    md_urls.each do |url|
      target_id = Utils.resolve_markdown_path_to_id(url, note.path, @notebook_path, db)
      if target_id
        db.execute('INSERT INTO links (source_id, target_id, link_type) VALUES (?, ?, ?)', [note.id, target_id, 'markdown'])
        new_targets << target_id
        markdown_inserts += 1
        debug_print("resolved markdown link #{url.inspect} -> #{target_id}")
      else
        debug_print("unresolved markdown link: #{url.inspect}")
      end
    end
    new_targets.uniq!
    debug_print("links: inserted #{wikilink_inserts} wikilink, #{markdown_inserts} markdown for source_id=#{note.id}")

    # Backlinks section: update this note and every note that is old or new target of this note
    note_ids_to_update = ([note.id] + old_targets + new_targets).uniq
    note_ids_to_update.each do |nid|
      update_backlinks_section(nid, db)
    end

    # Extract and store all tags (frontmatter + body)
    frontmatter_tags = note.metadata['tags']
    extract_and_store_tags(note.id, frontmatter_tags, body, db)

    db.close
  end

  # Returns array of all note ids in the index. Returns [] if the database does not exist.
  def indexed_note_ids
    return [] unless File.exist?(@db_path)

    db = SQLite3::Database.new(@db_path)
    rows = db.execute('SELECT id FROM notes')
    db.close
    rows.flatten
  end

  # Updates only the links table and backlinks sections for a note already in the index. Used by reindex second pass.
  # Re-reads note from disk (note.path). No-op if the note's id is not in notes.
  def update_links_for_note(note)
    return unless File.exist?(@db_path)
    db = SQLite3::Database.new(@db_path)
    setup_schema(db)
    return unless db.execute('SELECT 1 FROM notes WHERE id = ?', [note.id]).first

    body = note.body || ''
    description = note.metadata['description'].to_s
    old_targets = db.execute('SELECT target_id FROM links WHERE source_id = ?', [note.id]).flatten.uniq
    db.execute('DELETE FROM links WHERE source_id = ?', [note.id])
    new_targets = []
    body_with_desc = [body, description].reject(&:empty?).join("\n")
    Utils.extract_wikilinks(body_with_desc).each do |target|
      target_id = Utils.resolve_wikilink_to_id(target, db)
      if target_id
        db.execute('INSERT INTO links (source_id, target_id, link_type) VALUES (?, ?, ?)', [note.id, target_id, 'wikilink'])
        new_targets << target_id
      end
    end
    Utils.extract_markdown_link_urls(body_with_desc).each do |url|
      target_id = Utils.resolve_markdown_path_to_id(url, note.path, @notebook_path, db)
      if target_id
        db.execute('INSERT INTO links (source_id, target_id, link_type) VALUES (?, ?, ?)', [note.id, target_id, 'markdown'])
        new_targets << target_id
      end
    end
    new_targets.uniq!
    note_ids_to_update = ([note.id] + old_targets + new_targets).uniq
    note_ids_to_update.each do |nid|
      update_backlinks_section(nid, db)
    end
    db.close
  end

  # Removes notes by id from the index. FTS, links, and tags are updated. No-op if ids empty or DB missing.
  def remove_notes(ids)
    return if ids.nil? || ids.empty?
    return unless File.exist?(@db_path)

    db = SQLite3::Database.new(@db_path)
    setup_schema(db)
    placeholders = (['?'] * ids.size).join(', ')
    db.execute("DELETE FROM links WHERE source_id IN (#{placeholders}) OR target_id IN (#{placeholders})", ids + ids)
    db.execute("DELETE FROM tags WHERE note_id IN (#{placeholders})", ids)
    db.execute("DELETE FROM notes WHERE id IN (#{placeholders})", ids)
    db.close
  end

  private

  # Creates notes table, links table, FTS index, tags table, and triggers if not present.
  def setup_schema(db)
    setup_notes_table(db)
    setup_links_table(db)
    setup_fts_index(db)
    setup_tags_table(db)
    setup_triggers(db)
  end

  # Creates links table if not exists (source_id, target_id, link_type, context).
  def setup_links_table(db)
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS links (
        source_id TEXT NOT NULL,
        target_id TEXT NOT NULL,
        link_type TEXT,
        context TEXT
      )
    SQL
    db.execute('CREATE INDEX IF NOT EXISTS idx_links_source_id ON links(source_id)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_links_target_id ON links(target_id)')
  end

  # Creates notes table if not exists.
  def setup_notes_table(db)
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY,
        path TEXT,
        metadata TEXT,
        title TEXT,
        body TEXT,
        filename TEXT
      )
    SQL
    
    # Add new columns to existing table if they don't exist (migration)
    begin
      db.execute('ALTER TABLE notes ADD COLUMN title TEXT')
    rescue SQLite3::SQLException
      # Column already exists, ignore
    end
    
    begin
      db.execute('ALTER TABLE notes ADD COLUMN body TEXT')
    rescue SQLite3::SQLException
      # Column already exists, ignore
    end
    
    begin
      db.execute('ALTER TABLE notes ADD COLUMN filename TEXT')
    rescue SQLite3::SQLException
      # Column already exists, ignore
    end
  end

  # Creates FTS5 virtual table if not exists.
  def setup_fts_index(db)
    db.execute <<-SQL
      CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
        title,
        filename,
        full_text,
        id UNINDEXED
      )
    SQL
  end

  # Creates unified tags table for both frontmatter and body tags.
  # source: 'frontmatter' or 'body'
  def setup_tags_table(db)
    # Migrate from old body_tags table if it exists
    migrate_body_tags_table(db)

    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS tags (
        note_id TEXT NOT NULL,
        tag TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'frontmatter',
        PRIMARY KEY (note_id, tag, source)
      )
    SQL
    db.execute('CREATE INDEX IF NOT EXISTS idx_tags_tag ON tags(tag)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_tags_note ON tags(note_id)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_tags_source ON tags(source)')
  end

  # Migrates data from old body_tags table to unified tags table.
  def migrate_body_tags_table(db)
    # Check if body_tags table exists
    exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='body_tags'").any?
    return unless exists

    # Check if tags table exists; if not, migration will happen after tags table is created
    tags_exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='tags'").any?
    if tags_exists
      # Migrate data
      db.execute <<-SQL
        INSERT OR IGNORE INTO tags (note_id, tag, source)
        SELECT note_id, tag, 'body' FROM body_tags
      SQL
    end

    # Drop old table
    db.execute('DROP TABLE IF EXISTS body_tags')
    debug_print('Migrated body_tags to unified tags table')
  end

  # Creates INSERT/UPDATE/DELETE triggers to keep notes_fts in sync.
  def setup_triggers(db)
    # Drop existing triggers if they exist (for idempotency)
    db.execute('DROP TRIGGER IF EXISTS fts_insert')
    db.execute('DROP TRIGGER IF EXISTS fts_update')
    db.execute('DROP TRIGGER IF EXISTS fts_delete')

    # Create INSERT trigger
    db.execute <<-SQL
      CREATE TRIGGER fts_insert
        AFTER INSERT ON notes
      BEGIN
        INSERT INTO notes_fts(id, title, filename, full_text)
        VALUES (NEW.id, COALESCE(NEW.title, ''), COALESCE(NEW.filename, ''), COALESCE(NEW.body, ''));
      END
    SQL

    # Create UPDATE trigger
    db.execute <<-SQL
      CREATE TRIGGER fts_update
        AFTER UPDATE ON notes
      BEGIN
        UPDATE notes_fts
        SET title = COALESCE(NEW.title, ''),
            filename = COALESCE(NEW.filename, ''),
            full_text = COALESCE(NEW.body, '')
        WHERE id = NEW.id;
      END
    SQL

    # Create DELETE trigger
    db.execute <<-SQL
      CREATE TRIGGER fts_delete
        AFTER DELETE ON notes
      BEGIN
        DELETE FROM notes_fts WHERE id = OLD.id;
      END
    SQL
  end

  # Returns concatenated string content of a heading node (which may have child text nodes).
  def heading_string_content(heading_node)
    return '' unless heading_node.type == :heading
    parts = []
    heading_node.walk do |n|
      next unless n.type == :text
      parts << n.string_content.to_s
    end
    parts.join
  end

  # Returns basename of path.
  def extract_filename(path)
    return '' if path.nil? || path.empty?
    File.basename(path)
  end

  # Updates the ## Backlinks section in the note file for the given note id. Reads file, removes existing section, appends new one from links table.
  # Backlinks are rendered as markdown links [title](file_relative_path). Content before the section is preserved byte-for-byte (no re-parse).
  # Paths are computed relative to the note's directory so they work with standard markdown link resolution.
  def update_backlinks_section(note_id, db)
    row = db.execute('SELECT path FROM notes WHERE id = ?', [note_id]).first
    return unless row
    note_rel_path = row[0]
    note_path = File.join(@notebook_path, note_rel_path)
    return unless File.exist?(note_path)

    content = File.read(note_path)
    metadata, body = Utils.parse_front_matter(content)
    body_str = body.to_s
    source_ids = db.execute('SELECT source_id FROM links WHERE target_id = ? ORDER BY source_id', [note_id]).flatten.uniq

    # Find start of existing ## Backlinks section in raw body (preserve content before it without re-serializing)
    backlinks_start = body_str.match(/^## Backlinks\s*$/m)
    kept_md = if backlinks_start
                body_str[0...backlinks_start.begin(0)].rstrip
              else
                body_str.rstrip
              end

    # When no backlinks and no existing section to remove, do not touch the file
    if source_ids.empty? && backlinks_start.nil?
      return
    end

    if source_ids.empty?
      new_body = kept_md
    else
      # Fetch path and title for each source (notebook-relative path; title with fallback)
      placeholders = (['?'] * source_ids.size).join(', ')
      rows = db.execute("SELECT id, path, title FROM notes WHERE id IN (#{placeholders})", source_ids)
      id_to_path_title = rows.to_h { |id, path, title| [id, { path: path.to_s.gsub(File::SEPARATOR, '/'), title: title.to_s.strip }] }

      # Compute file-relative paths from the note's directory
      note_dir = Pathname.new(note_rel_path).dirname

      backlinks_md = +"## Backlinks\n\n"
      source_ids.each do |id|
        info = id_to_path_title[id] || { path: id, title: id }
        source_rel_path = info[:path]
        title = info[:title]
        title = File.basename(source_rel_path, '.md') if title.empty?
        title = id if title.empty?

        # Compute relative path from note's directory to source file
        source_pathname = Pathname.new(source_rel_path)
        relative_path = source_pathname.relative_path_from(note_dir).to_s

        # Minimal escaping so [link text](url) is valid CommonMark (\] in text, \) in url)
        text_esc = title.to_s.gsub('\\', '\\\\').gsub(']', '\\]')
        url_esc = relative_path.to_s.gsub('\\', '\\\\').gsub(')', '\\)')
        backlinks_md << "- [#{text_esc}](#{url_esc})\n"
      end
      new_body = (kept_md + "\n\n" + backlinks_md).strip
    end

    # Write without re-parsing body so existing content is not reformatted
    front_matter_yaml = metadata.to_yaml.sub(/^---\n/, '')
    new_content = "---\n#{front_matter_yaml}---\n\n#{new_body}"
    return if new_content == content
    File.write(note_path, new_content)
    debug_print("Updated backlinks section: #{note_path} (#{source_ids.size} backlinks)")
  end

  # Extracts and stores all tags (frontmatter and body) in unified tags table.
  def extract_and_store_tags(note_id, frontmatter_tags, body, db)
    # Delete existing tags for this note
    db.execute('DELETE FROM tags WHERE note_id = ?', [note_id])

    # Store frontmatter tags
    fm_tags = normalize_tag_array(frontmatter_tags)
    fm_tags.each do |tag|
      db.execute('INSERT OR IGNORE INTO tags (note_id, tag, source) VALUES (?, ?, ?)', [note_id, tag, 'frontmatter'])
    end

    # Extract and store body hashtags if enabled
    body_tags = []
    if @extract_body_hashtags
      body_tags = extract_body_hashtags(body)
      body_tags.each do |tag|
        db.execute('INSERT OR IGNORE INTO tags (note_id, tag, source) VALUES (?, ?, ?)', [note_id, tag, 'body'])
      end
    end

    debug_print("Stored #{fm_tags.size} frontmatter tag(s), #{body_tags.size} body hashtag(s)")
  end

  # Normalizes tag array: converts to strings, optionally lowercases, removes empty.
  def normalize_tag_array(tags)
    return [] if tags.nil?

    tags = Array(tags).map(&:to_s).reject(&:empty?)
    normalize = @config.dig('tags', 'normalize') != false
    tags = tags.map(&:downcase) if normalize
    tags.uniq
  end

  # Extracts hashtags from body text, excluding code blocks.
  # Returns array of lowercase tag names (without #).
  def extract_body_hashtags(body)
    return [] if body.to_s.empty?

    # Remove code blocks (fenced and inline)
    body_without_code = body.gsub(/```[\s\S]*?```/m, '')
                            .gsub(/`[^`]+`/, '')
    
    # Extract hashtags
    hashtags = body_without_code.scan(HASHTAG_PATTERN).flatten
    
    # Normalize: lowercase and unique
    normalize_tags = @config.dig('tags', 'normalize') != false
    if normalize_tags
      hashtags = hashtags.map(&:downcase)
    end
    
    # Apply exclusion patterns
    excluded_patterns = @config.dig('tags', 'excluded_patterns') || []
    excluded_patterns.each do |pattern|
      regex = Regexp.new(pattern)
      hashtags = hashtags.reject { |tag| tag.match?(regex) }
    end
    
    # Apply min/max length
    min_length = @config.dig('tags', 'min_length') || 2
    max_length = @config.dig('tags', 'max_length') || 50
    hashtags = hashtags.select { |tag| tag.length >= min_length && tag.length <= max_length }
    
    hashtags.uniq
  end
end
