# frozen_string_literal: true

require_relative 'organization'

# Account: customer organization tracked in external systems.
# CRM-specific fields are template-defined metadata accessed via metadata hash.
# Example: account.metadata['crm']['segment'], account.metadata['revenue'], etc.
# This keeps the model generic; custom fields are defined in templates.
class Account < Organization
  # Initializes an Account from a file path.
  # Inherits all Organization behavior.
  def initialize(opts = {})
    super(opts)
    # Ensure type is set correctly if not specified
    @type ||= 'account'
  end
end
