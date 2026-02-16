# frozen_string_literal: true

require_relative 'document'
require_relative '../utils'

# Organization resource: base class for companies, institutions, groups.
# Provides accessors for common organization fields stored in front matter.
class Organization < Document
  # Initializes an Organization from a file path.
  # Reads file content and parses front matter for metadata.
  def initialize(opts = {})
    path = opts[:path] || opts['path']
    raise ArgumentError, 'path is required' unless path

    file_content = File.read(path)
    metadata, body = Utils.parse_front_matter(file_content)
    metadata = (opts[:metadata] || opts['metadata'] || {}).merge(metadata)

    document_opts = {
      id: opts[:id] || opts['id'] || metadata['id']&.to_s || Document.generate_id,
      path: path,
      title: opts[:title] || opts['title'] || metadata['title'],
      type: opts[:type] || opts['type'] || metadata['type'] || 'organization',
      date: opts[:date] || opts['date'] || metadata['date'],
      content: body,
      metadata: metadata,
      body: body
    }

    super(document_opts)
  end

  # Returns the organization name from metadata, falling back to title.
  def name
    metadata['name'] || metadata[:name] || title
  end

  # Returns the website URL.
  def website
    metadata['website'] || metadata[:website]
  end

  # Returns the industry/sector.
  def industry
    metadata['industry'] || metadata[:industry]
  end

  # Returns the address.
  def address
    metadata['address'] || metadata[:address]
  end

  # Returns the parent organization wikilink.
  def parent
    metadata['parent'] || metadata[:parent]
  end

  # Returns array of subsidiary wikilinks.
  def subsidiaries
    Array(metadata['subsidiaries'] || metadata[:subsidiaries])
  end

  # Returns aliases array.
  def aliases
    Array(metadata['aliases'] || metadata[:aliases])
  end

  # Returns tags array.
  def tags
    Array(metadata['tags'] || metadata[:tags])
  end

  # Returns the parent organization ID extracted from wikilink.
  def parent_id
    Utils.extract_id_from_wikilink(parent)
  end

  # Returns array of subsidiary IDs extracted from wikilinks.
  def subsidiary_ids
    subsidiaries.map { |link| Utils.extract_id_from_wikilink(link) }.compact
  end
end
