# frozen_string_literal: true

# Shared debug behavior for commands that use ZH_DEBUG.
module Debug
  # Returns true when ZH_DEBUG=1.
  def debug?
    ENV['ZH_DEBUG'] == '1'
  end

  # Prints message to stderr when debug? is true.
  def debug_print(message)
    return unless debug?

    $stderr.puts("[DEBUG] #{message}")
  end
end
