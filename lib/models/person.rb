# frozen_string_literal: true

require_relative 'document'
require_relative '../utils'

# Person resource: contact information from metadata.
# Provides accessors for common contact fields stored in front matter.
class Person < Document
  # Initializes a Person from a file path.
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
      type: opts[:type] || opts['type'] || metadata['type'] || 'person',
      date: opts[:date] || opts['date'] || metadata['date'],
      content: body,
      metadata: metadata,
      body: body
    }

    super(document_opts)
  end

  # Returns the person's full name from metadata, falling back to title.
  def full_name
    metadata['full_name'] || metadata[:full_name] || title
  end

  # Returns array of email addresses.
  def emails
    Array(metadata['emails'] || metadata[:emails])
  end

  # Returns the primary email address.
  def email
    emails.first
  end

  # Returns array of phone numbers.
  def phones
    Array(metadata['phones'] || metadata[:phones])
  end

  # Returns the primary phone number.
  def phone
    phones.first
  end

  # Returns the organization wikilink or name.
  def organization
    metadata['organization'] || metadata[:organization]
  end

  # Returns the person's role/title at their organization.
  def role
    metadata['role'] || metadata[:role]
  end

  # Returns the birthday date string.
  def birthday
    metadata['birthday'] || metadata[:birthday]
  end

  # Returns the address.
  def address
    metadata['address'] || metadata[:address]
  end

  # Returns the website URL.
  def website
    metadata['website'] || metadata[:website]
  end

  # Returns social profile hash (linkedin, github, twitter, etc.).
  def social
    metadata['social'] || metadata[:social] || {}
  end

  # Returns array of relationship wikilinks.
  def relationships
    Array(metadata['relationships'] || metadata[:relationships])
  end

  # Returns the last contact date string.
  def last_contact
    metadata['last_contact'] || metadata[:last_contact]
  end

  # Returns aliases array.
  def aliases
    Array(metadata['aliases'] || metadata[:aliases])
  end

  # Returns tags array.
  def tags
    Array(metadata['tags'] || metadata[:tags])
  end
end
