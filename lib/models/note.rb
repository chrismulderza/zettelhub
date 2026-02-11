# frozen_string_literal: true

require_relative '../utils'
require_relative 'document'

# Base class for notes in ZettelHub
class Note < Document
  # Loads note from path, parses front matter, merges opts and file metadata, initializes Document.
  def initialize(opts = {})
    # Require path in opts
    path = opts[:path] || opts['path']
    raise ArgumentError, 'path is required' unless path

    # Read and parse file
    file_content = File.read(path)
    metadata, body = Utils.parse_front_matter(file_content)

    # Merge metadata from opts if provided
    metadata = (opts[:metadata] || opts['metadata'] || {}).merge(metadata)

    # Map file-based initialization to Document's attribute structure
    document_opts = {
      id: opts[:id] || opts['id'] || metadata['id']&.to_s || Document.generate_id,
      path: path,
      title: opts[:title] || opts['title'] || metadata['title'],
      type: opts[:type] || opts['type'] || metadata['type'],
      date: opts[:date] || opts['date'] || metadata['date'],
      content: body,
      metadata: metadata,
      body: body
    }

    super(document_opts)
  end
end
