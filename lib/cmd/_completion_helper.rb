#!/usr/bin/env ruby
# frozen_string_literal: true

# Completion helper: common_options returns shared flags; other commands use --completion.

def get_common_options
  %w[--help --version]
end

# Main entry point
command = ARGV[0]

case command
when 'common_options'
  puts get_common_options.join(' ')
else
  puts ''
end
