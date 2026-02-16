# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require 'fileutils'
require_relative '../../lib/models/organization'
require_relative '../../lib/models/account'

class OrganizationTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def create_org_file(content)
    path = File.join(@tmpdir, 'org.md')
    File.write(path, content)
    path
  end

  def test_initialize_reads_file_and_parses_metadata
    path = create_org_file(<<~MD)
      ---
      id: org12345
      type: organization
      title: Acme Corporation
      name: Acme Corporation
      website: https://acme.com
      industry: Technology
      parent: "[[parent123|Parent Corp]]"
      subsidiaries:
        - "[[sub1|Subsidiary One]]"
        - "[[sub2|Subsidiary Two]]"
      ---
      # Acme Corporation

      Notes about the organization.
    MD

    org = Organization.new(path: path)

    assert_equal 'org12345', org.id
    assert_equal 'organization', org.type
    assert_equal 'Acme Corporation', org.title
    assert_equal 'Acme Corporation', org.name
    assert_equal 'https://acme.com', org.website
    assert_equal 'Technology', org.industry
    assert_equal '[[parent123|Parent Corp]]', org.parent
    assert_equal 2, org.subsidiaries.size
  end

  def test_initialize_requires_path
    assert_raises(ArgumentError) do
      Organization.new({})
    end
  end

  def test_name_falls_back_to_title
    path = create_org_file(<<~MD)
      ---
      id: org12345
      type: organization
      title: Test Organization
      ---
    MD

    org = Organization.new(path: path)

    assert_equal 'Test Organization', org.name
  end

  def test_subsidiaries_returns_empty_array_when_nil
    path = create_org_file(<<~MD)
      ---
      id: org12345
      type: organization
      title: Test Organization
      ---
    MD

    org = Organization.new(path: path)

    assert_equal [], org.subsidiaries
  end

  def test_parent_id_extracts_from_wikilink
    path = create_org_file(<<~MD)
      ---
      id: org12345
      type: organization
      title: Test Organization
      parent: "[[parent123|Parent Corp]]"
      ---
    MD

    org = Organization.new(path: path)

    assert_equal 'parent123', org.parent_id
  end

  def test_subsidiary_ids_extracts_from_wikilinks
    path = create_org_file(<<~MD)
      ---
      id: org12345
      type: organization
      title: Test Organization
      subsidiaries:
        - "[[sub1|Subsidiary One]]"
        - "[[sub2|Subsidiary Two]]"
      ---
    MD

    org = Organization.new(path: path)

    assert_equal %w[sub1 sub2], org.subsidiary_ids
  end

  def test_address_accessor
    path = create_org_file(<<~MD)
      ---
      id: org12345
      type: organization
      title: Test Organization
      address: "123 Main St, City, Country"
      ---
    MD

    org = Organization.new(path: path)

    assert_equal '123 Main St, City, Country', org.address
  end

  def test_aliases_and_tags_accessors
    path = create_org_file(<<~MD)
      ---
      id: org12345
      type: organization
      title: Test Organization
      aliases:
        - "org> Test Organization"
      tags:
        - organization
        - tech
      ---
    MD

    org = Organization.new(path: path)

    assert_includes org.aliases, 'org> Test Organization'
    assert_equal %w[organization tech], org.tags
  end
end

class AccountTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def create_account_file(content)
    path = File.join(@tmpdir, 'account.md')
    File.write(path, content)
    path
  end

  def test_account_inherits_from_organization
    path = create_account_file(<<~MD)
      ---
      id: acc12345
      type: account
      title: Customer Account
      name: Customer Account
      website: https://customer.com
      parent: "[[parent123|Holding Company]]"
      crm:
        segment: Enterprise
        territory: North America
        owner: John Doe
      ---
    MD

    account = Account.new(path: path)

    # Inherited from Organization
    assert_equal 'acc12345', account.id
    assert_equal 'account', account.type
    assert_equal 'Customer Account', account.name
    assert_equal 'https://customer.com', account.website
    assert_equal '[[parent123|Holding Company]]', account.parent
  end

  def test_account_custom_metadata_accessed_via_metadata_hash
    path = create_account_file(<<~MD)
      ---
      id: acc12345
      type: account
      title: Customer Account
      crm:
        segment: Enterprise
        territory: North America
        owner: John Doe
      revenue: 1000000
      ---
    MD

    account = Account.new(path: path)

    # Custom fields are accessed via metadata hash, not model methods
    assert_equal 'Enterprise', account.metadata['crm']['segment']
    assert_equal 'North America', account.metadata['crm']['territory']
    assert_equal 'John Doe', account.metadata['crm']['owner']
    assert_equal 1_000_000, account.metadata['revenue']
  end
end
