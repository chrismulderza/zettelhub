require 'minitest/autorun'
require_relative '../../lib/cmd/_completion_helper'

class CompletionHelperTest < Minitest::Test
  def test_get_common_options_returns_expected_options
    # Since get_common_options is a top-level function, we need to test it differently
    # We can test by running the script and capturing output
    output = `ruby #{File.join(__dir__, '../../lib/cmd/_completion_helper.rb')} common_options`.strip
    assert_includes output, '--help'
    assert_includes output, '--version'
  end

  def test_unknown_command_returns_empty
    output = `ruby #{File.join(__dir__, '../../lib/cmd/_completion_helper.rb')} unknown`.strip
    assert_equal '', output
  end

  def test_common_options_contains_help_and_version
    # Test the function directly by loading the file
    load File.join(__dir__, '../../lib/cmd/_completion_helper.rb')
    # After loading, the function should be available
    # We can't easily test it directly, so we test via script execution
    output = `ruby #{File.join(__dir__, '../../lib/cmd/_completion_helper.rb')} common_options`.strip
    options = output.split(' ')
    assert_includes options, '--help'
    assert_includes options, '--version'
    assert_equal 2, options.length
  end

  def test_no_argument_returns_empty
    output = `ruby #{File.join(__dir__, '../../lib/cmd/_completion_helper.rb')}`.strip
    assert_equal '', output
  end
end
