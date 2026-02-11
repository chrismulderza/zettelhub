# frozen_string_literal: true

require_relative 'resource'

# Bookmark resource: has uri from metadata (required for bookmarks).
class Bookmark < Resource
  # URI from metadata (bookmark location).
  def uri
    metadata['uri'] || metadata[:uri]
  end
end
