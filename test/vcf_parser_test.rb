# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/vcf_parser'

class VcfParserTest < Minitest::Test
  def test_parse_simple_vcard
    vcf = <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      FN:John Doe
      EMAIL:john@example.com
      TEL:+1-555-1234
      END:VCARD
    VCF

    contacts = VcfParser.parse(vcf)

    assert_equal 1, contacts.size
    contact = contacts.first
    assert_equal 'John Doe', contact[:full_name]
    assert_includes contact[:emails], 'john@example.com'
    assert_includes contact[:phones], '+1-555-1234'
  end

  def test_parse_multiple_vcards
    vcf = <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      FN:John Doe
      END:VCARD
      BEGIN:VCARD
      VERSION:3.0
      FN:Jane Smith
      END:VCARD
    VCF

    contacts = VcfParser.parse(vcf)

    assert_equal 2, contacts.size
    assert_equal 'John Doe', contacts[0][:full_name]
    assert_equal 'Jane Smith', contacts[1][:full_name]
  end

  def test_parse_structured_name
    vcf = <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      N:Doe;John;William;Mr.;Jr.
      END:VCARD
    VCF

    contacts = VcfParser.parse(vcf)
    contact = contacts.first

    # Full name built from N when FN not present
    assert_includes contact[:full_name], 'John'
    assert_includes contact[:full_name], 'Doe'
  end

  def test_parse_multiple_emails
    vcf = <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      FN:John Doe
      EMAIL:john@work.com
      EMAIL:john@personal.com
      END:VCARD
    VCF

    contacts = VcfParser.parse(vcf)
    contact = contacts.first

    assert_equal 2, contact[:emails].size
    assert_includes contact[:emails], 'john@work.com'
    assert_includes contact[:emails], 'john@personal.com'
  end

  def test_parse_organization_and_role
    vcf = <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      FN:John Doe
      ORG:Acme Corp
      TITLE:Software Engineer
      END:VCARD
    VCF

    contacts = VcfParser.parse(vcf)
    contact = contacts.first

    assert_equal 'Acme Corp', contact[:organization]
    assert_equal 'Software Engineer', contact[:role]
  end

  def test_parse_birthday
    vcf = <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      FN:John Doe
      BDAY:19800115
      END:VCARD
    VCF

    contacts = VcfParser.parse(vcf)
    contact = contacts.first

    assert_equal '1980-01-15', contact[:birthday]
  end

  def test_parse_url
    vcf = <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      FN:John Doe
      URL:https://johndoe.com
      END:VCARD
    VCF

    contacts = VcfParser.parse(vcf)
    contact = contacts.first

    assert_equal 'https://johndoe.com', contact[:website]
  end

  def test_parse_note
    vcf = <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      FN:John Doe
      NOTE:Some notes about John
      END:VCARD
    VCF

    contacts = VcfParser.parse(vcf)
    contact = contacts.first

    assert_equal 'Some notes about John', contact[:notes]
  end

  def test_parse_categories_as_tags
    vcf = <<~VCF
      BEGIN:VCARD
      VERSION:3.0
      FN:John Doe
      CATEGORIES:work,friend,developer
      END:VCARD
    VCF

    contacts = VcfParser.parse(vcf)
    contact = contacts.first

    assert_equal %w[work friend developer], contact[:tags]
  end

  def test_unescape_special_characters
    assert_equal "Hello\nWorld", VcfParser.unescape('Hello\\nWorld')
    assert_equal 'Hello,World', VcfParser.unescape('Hello\\,World')
    assert_equal 'Hello;World', VcfParser.unescape('Hello\\;World')
    assert_equal 'Hello\\World', VcfParser.unescape('Hello\\\\World')
  end

  def test_escape_special_characters
    assert_equal 'Hello\\nWorld', VcfParser.escape("Hello\nWorld")
    assert_equal 'Hello\\,World', VcfParser.escape('Hello,World')
    assert_equal 'Hello\\;World', VcfParser.escape('Hello;World')
  end

  def test_to_vcard_basic
    contact = {
      full_name: 'John Doe',
      emails: ['john@example.com'],
      phones: ['+1-555-1234']
    }

    vcard = VcfParser.to_vcard(contact)

    assert_includes vcard, 'BEGIN:VCARD'
    assert_includes vcard, 'END:VCARD'
    assert_includes vcard, 'FN:John Doe'
    assert_includes vcard, 'EMAIL:john@example.com'
    assert_includes vcard, 'TEL:+1-555-1234'
  end

  def test_to_vcard_with_all_fields
    contact = {
      full_name: 'John Doe',
      emails: ['john@example.com'],
      phones: ['+1-555-1234'],
      organization: 'Acme Corp',
      role: 'Engineer',
      birthday: '1980-01-15',
      website: 'https://johndoe.com',
      notes: 'Some notes',
      tags: %w[work friend]
    }

    vcard = VcfParser.to_vcard(contact)

    assert_includes vcard, 'ORG:Acme Corp'
    assert_includes vcard, 'TITLE:Engineer'
    assert_includes vcard, 'BDAY:19800115'
    assert_includes vcard, 'URL:https://johndoe.com'
    assert_includes vcard, 'NOTE:Some notes'
    assert_includes vcard, 'CATEGORIES:work,friend'
  end

  def test_parse_date_formats
    assert_equal '1980-01-15', VcfParser.parse_date('19800115')
    assert_equal '1980-01-15', VcfParser.parse_date('1980-01-15')
    assert_nil VcfParser.parse_date('')
    assert_nil VcfParser.parse_date(nil)
  end
end
