require 'minitest/autorun'
require 'tempfile'
require_relative '../../lib/models/meeting'

class MeetingTest < Minitest::Test
  def test_meeting_inherits_from_note
    assert Meeting < Note, 'Meeting should inherit from Note'
  end

  def test_meeting_initialization_with_path
    content = <<~EOF
      ---
      id: meeting-123
      type: meeting
      title: Standup Meeting
      date: 2025-01-23
      ---
      # Meeting Notes
      Discussion points...
    EOF
    file = Tempfile.new(['meeting', '.md'])
    file.write(content)
    file.close
    meeting = Meeting.new(path: file.path)
    assert_equal 'meeting-123', meeting.id
    assert_equal 'meeting', meeting.type
    assert_equal 'Standup Meeting', meeting.title
    # Date is parsed as Date object by YAML when using YYYY-MM-DD format
    if meeting.date.is_a?(Date)
      assert_equal Date.new(2025, 1, 23), meeting.date
    else
      assert_equal '2025-01-23', meeting.date
    end
    assert_includes meeting.content, "Meeting Notes"
  end

  def test_meeting_initialization_without_path_raises_error
    assert_raises(ArgumentError, 'path is required') do
      Meeting.new
    end
  end

  def test_meeting_inherits_note_methods
    content = <<~EOF
      ---
      id: meeting-test
      type: meeting
      ---
      # Content
    EOF
    file = Tempfile.new(['meeting', '.md'])
    file.write(content)
    file.close
    meeting = Meeting.new(path: file.path)
    # Verify it has all Note attributes
    assert meeting.id
    assert meeting.respond_to?(:title)
    assert meeting.respond_to?(:type)
    assert meeting.respond_to?(:path)
    assert meeting.respond_to?(:date)
    assert meeting.respond_to?(:content)
    assert meeting.respond_to?(:metadata)
    assert meeting.respond_to?(:body)
  end

  def test_meeting_with_metadata
    content = <<~EOF
      ---
      id: meeting-meta
      type: meeting
      title: "Team Sync"
      attendees:
        - Alice
        - Bob
        - Charlie
      ---
      # Notes
    EOF
    file = Tempfile.new(['meeting', '.md'])
    file.write(content)
    file.close
    meeting = Meeting.new(path: file.path)
    assert_equal 'Team Sync', meeting.title
    assert_equal ['Alice', 'Bob', 'Charlie'], meeting.metadata['attendees']
  end
end
