# frozen_string_literal: true

require 'minitest/autorun'
require 'tempfile'
require 'fileutils'
require_relative '../../lib/models/person'

class PersonTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def create_person_file(content)
    path = File.join(@tmpdir, 'person.md')
    File.write(path, content)
    path
  end

  def test_initialize_reads_file_and_parses_metadata
    path = create_person_file(<<~MD)
      ---
      id: abc12345
      type: person
      title: John Doe
      full_name: John Doe
      emails:
        - john@example.com
      phones:
        - "+1-555-1234"
      organization: "[[org123|Acme Corp]]"
      role: Software Engineer
      ---
      # John Doe

      Some notes about John.
    MD

    person = Person.new(path: path)

    assert_equal 'abc12345', person.id
    assert_equal 'person', person.type
    assert_equal 'John Doe', person.title
    assert_equal 'John Doe', person.full_name
    assert_equal ['john@example.com'], person.emails
    assert_equal 'john@example.com', person.email
    assert_equal ['+1-555-1234'], person.phones
    assert_equal '+1-555-1234', person.phone
    assert_equal '[[org123|Acme Corp]]', person.organization
    assert_equal 'Software Engineer', person.role
  end

  def test_initialize_requires_path
    assert_raises(ArgumentError) do
      Person.new({})
    end
  end

  def test_full_name_falls_back_to_title
    path = create_person_file(<<~MD)
      ---
      id: abc12345
      type: person
      title: Jane Smith
      ---
    MD

    person = Person.new(path: path)

    assert_equal 'Jane Smith', person.full_name
  end

  def test_emails_returns_empty_array_when_nil
    path = create_person_file(<<~MD)
      ---
      id: abc12345
      type: person
      title: Test Person
      ---
    MD

    person = Person.new(path: path)

    assert_equal [], person.emails
    assert_nil person.email
  end

  def test_birthday_accessor
    path = create_person_file(<<~MD)
      ---
      id: abc12345
      type: person
      title: Test Person
      birthday: "1980-01-15"
      ---
    MD

    person = Person.new(path: path)

    assert_equal '1980-01-15', person.birthday
  end

  def test_social_accessor
    path = create_person_file(<<~MD)
      ---
      id: abc12345
      type: person
      title: Test Person
      social:
        linkedin: johndoe
        github: jdoe
      ---
    MD

    person = Person.new(path: path)

    assert_equal({ 'linkedin' => 'johndoe', 'github' => 'jdoe' }, person.social)
  end

  def test_relationships_accessor
    path = create_person_file(<<~MD)
      ---
      id: abc12345
      type: person
      title: Test Person
      relationships:
        - "[[rel1|Manager]]"
        - "[[rel2|Colleague]]"
      ---
    MD

    person = Person.new(path: path)

    assert_equal ['[[rel1|Manager]]', '[[rel2|Colleague]]'], person.relationships
  end

  def test_last_contact_accessor
    path = create_person_file(<<~MD)
      ---
      id: abc12345
      type: person
      title: Test Person
      last_contact: "2025-01-10"
      ---
    MD

    person = Person.new(path: path)

    assert_equal '2025-01-10', person.last_contact
  end

  def test_aliases_accessor
    path = create_person_file(<<~MD)
      ---
      id: abc12345
      type: person
      title: Test Person
      aliases:
        - "person> Test Person"
        - "@Test Person"
      ---
    MD

    person = Person.new(path: path)

    assert_includes person.aliases, 'person> Test Person'
    assert_includes person.aliases, '@Test Person'
  end

  def test_tags_accessor
    path = create_person_file(<<~MD)
      ---
      id: abc12345
      type: person
      title: Test Person
      tags:
        - contact
        - work
      ---
    MD

    person = Person.new(path: path)

    assert_equal %w[contact work], person.tags
  end
end
