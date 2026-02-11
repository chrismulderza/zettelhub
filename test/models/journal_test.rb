require 'minitest/autorun'
require 'tempfile'
require_relative '../../lib/models/journal'

class JournalTest < Minitest::Test
  def test_journal_inherits_from_note
    assert Journal < Note, 'Journal should inherit from Note'
  end

  def test_journal_initialization_with_path
    content = <<~EOF
      ---
      id: journal-123
      type: journal
      date: 2025-01-23
      ---
      # Journal Entry
      Today's thoughts...
    EOF
    file = Tempfile.new(['journal', '.md'])
    file.write(content)
    file.close
    journal = Journal.new(path: file.path)
    assert_equal 'journal-123', journal.id
    assert_equal 'journal', journal.type
    # Date is parsed as Date object by YAML when using YYYY-MM-DD format
    if journal.date.is_a?(Date)
      assert_equal Date.new(2025, 1, 23), journal.date
    else
      assert_equal '2025-01-23', journal.date
    end
    assert_includes journal.content, "Journal Entry"
  end

  def test_journal_initialization_without_path_raises_error
    assert_raises(ArgumentError, 'path is required') do
      Journal.new
    end
  end

  def test_journal_inherits_note_methods
    content = <<~EOF
      ---
      id: journal-test
      type: journal
      ---
      # Content
    EOF
    file = Tempfile.new(['journal', '.md'])
    file.write(content)
    file.close
    journal = Journal.new(path: file.path)
    # Verify it has all Note attributes
    assert journal.id
    assert journal.respond_to?(:title)
    assert journal.respond_to?(:type)
    assert journal.respond_to?(:path)
    assert journal.respond_to?(:date)
    assert journal.respond_to?(:content)
    assert journal.respond_to?(:metadata)
    assert journal.respond_to?(:body)
  end

  def test_journal_with_metadata
    content = <<~EOF
      ---
      id: journal-meta
      type: journal
      title: "Daily Journal"
      tags:
        - daily
        - reflection
      ---
      # Entry
    EOF
    file = Tempfile.new(['journal', '.md'])
    file.write(content)
    file.close
    journal = Journal.new(path: file.path)
    assert_equal 'Daily Journal', journal.title
    assert_equal ['daily', 'reflection'], journal.metadata['tags']
  end
end
