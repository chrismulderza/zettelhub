# frozen_string_literal: true

require 'securerandom'
require_relative '../utils'

# Base class from which everything inherits
class Document
  # Attributes: id, title, type, path, date, content, metadata, body
  attr_reader :id,
              :title,
              :type,
              :path,
              :date,
              :content,
              :metadata,
              :body

  # Initialise a new Document object. Pass a hash of options to the object to
  # initialise with an existing ID, or leave empty to generate a new ID.
  def initialize(opts = {})
    # Normalize opts to use symbols
    opts = opts.transform_keys(&:to_sym) if opts.is_a?(Hash)
    
    @id = opts.key?(:id) ? opts[:id] : Document.generate_id
    @path = opts[:path]
    @title = opts[:title]
    @type = opts[:type]
    @date = opts[:date]
    @content = opts[:content]
    @metadata = opts[:metadata] || {}
    @body = opts[:body]
  end

  # Class method that delegates to Utils.generate_id (8-char hex).
  def self.generate_id
    Utils.generate_id
  end
end
