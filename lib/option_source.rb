# frozen_string_literal: true

require 'json'
require 'sqlite3'
require_relative 'config'

# Resolves dynamic option sources for template prompts.
# Supports: tags, notes, files, command.
module OptionSource
  # Resolves options from a source definition.
  # Returns array of option strings.
  def self.resolve(source, config, vars = {})
    return [] if source.nil?

    source = { 'type' => source } if source.is_a?(String)
    return [] unless source.is_a?(Hash)

    type = source['type']&.to_s&.downcase
    options = case type
              when 'tags'
                resolve_tags(source, config)
              when 'notes'
                resolve_notes(source, config)
              when 'files'
                resolve_files(source, config)
              when 'command'
                resolve_command(source, vars)
              else
                []
              end

    # Apply filter if specified
    if source['filter']
      pattern = Regexp.new(source['filter'])
      options = options.select { |opt| opt.to_s.match?(pattern) }
    end

    # Apply transform if specified
    options = apply_transform(options, source['transform']) if source['transform']

    # Apply sort if specified
    options = apply_sort(options, source['sort'])

    # Apply limit if specified
    options = options.take(source['limit'].to_i) if source['limit']

    options
  end

  # Resolves tags from the index database.
  def self.resolve_tags(source, config)
    notebook_path = config['notebook_path']
    db_path = Config.index_db_path(notebook_path)
    return [] unless File.exist?(db_path)

    db = SQLite3::Database.new(db_path)
    tags = []

    # Query tags from metadata JSON
    rows = db.execute('SELECT metadata FROM notes WHERE metadata IS NOT NULL')
    tag_counts = Hash.new(0)

    rows.each do |row|
      meta = JSON.parse(row[0] || '{}')
      Array(meta['tags']).each do |tag|
        tag_counts[tag.to_s] += 1
      end
    rescue JSON::ParserError
      next
    end

    db.close

    # Return tags with counts for sorting
    tag_counts.map { |tag, count| { name: tag, count: count } }
  end

  # Resolves notes from the index database.
  def self.resolve_notes(source, config)
    notebook_path = config['notebook_path']
    db_path = Config.index_db_path(notebook_path)
    return [] unless File.exist?(db_path)

    db = SQLite3::Database.new(db_path)

    # Build query based on source options
    sql = 'SELECT id, title, path, metadata FROM notes WHERE 1=1'
    params = []

    # Filter by type if specified
    if source['filter_type']
      types = source['filter_type'].split('|').map(&:strip)
      placeholders = (['?'] * types.size).join(', ')
      sql += " AND json_extract(metadata, '$.type') IN (#{placeholders})"
      params.concat(types)
    end

    rows = db.execute(sql, params)
    db.close

    # Determine return format
    return_format = source['return']&.to_s&.downcase || 'title'
    field = source['field']&.to_s || 'title'

    rows.map do |id, title, path, metadata_json|
      meta = JSON.parse(metadata_json || '{}') rescue {}
      case return_format
      when 'wikilink'
        "[[#{id}|#{title}]]"
      when 'id'
        id
      when 'path'
        path
      when 'field'
        meta[field] || title
      else
        title
      end
    end.compact
  end

  # Resolves files from filesystem glob.
  def self.resolve_files(source, config)
    notebook_path = config['notebook_path']
    glob = source['glob'] || source['pattern'] || '**/*.md'
    base_path = source['base'] || notebook_path

    Dir.glob(File.join(base_path, glob)).map do |path|
      if source['return'] == 'basename'
        File.basename(path)
      elsif source['return'] == 'relative'
        path.sub("#{base_path}/", '')
      else
        path
      end
    end
  end

  # Resolves options from external command output.
  def self.resolve_command(source, vars)
    cmd = source['command'] || source['cmd']
    return [] unless cmd

    # Substitute variables in command
    vars.each do |key, value|
      cmd = cmd.gsub("{#{key}}", value.to_s)
    end

    output = `#{cmd} 2>/dev/null`
    output.split("\n").map(&:strip).reject(&:empty?)
  rescue StandardError
    []
  end

  # Applies transformation to options.
  def self.apply_transform(options, transform)
    case transform
    when /^strip_prefix:(.+)/
      prefix = Regexp.last_match(1)
      options.map { |opt| opt.to_s.sub(/\A#{Regexp.escape(prefix)}/, '') }
    when /^strip_suffix:(.+)/
      suffix = Regexp.last_match(1)
      options.map { |opt| opt.to_s.sub(/#{Regexp.escape(suffix)}\z/, '') }
    else
      options
    end
  end

  # Applies sorting to options.
  def self.apply_sort(options, sort_type)
    return options if sort_type.nil?

    case sort_type.to_s.downcase
    when 'alpha', 'alphabetical'
      if options.first.is_a?(Hash)
        options.sort_by { |opt| opt[:name].to_s.downcase }
      else
        options.sort_by { |opt| opt.to_s.downcase }
      end
    when 'count'
      if options.first.is_a?(Hash)
        options.sort_by { |opt| -opt[:count].to_i }
      else
        options
      end
    when 'recent'
      # For files, sort by mtime; for others, preserve order
      options
    else
      options
    end
  end

  # Extracts display values from options (handles hashes with :name).
  def self.to_display_values(options)
    options.map do |opt|
      opt.is_a?(Hash) ? opt[:name] : opt.to_s
    end
  end
end
