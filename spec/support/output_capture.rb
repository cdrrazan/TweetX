# frozen_string_literal: true

# Scheduler talks to the operator through stdout — the emoji status lines are
# the CLI's user interface, not debug noise. Specs capture that output instead
# of silencing it, so assertions can be made against what a user would see and
# the suite's own output stays readable.
module OutputCapture
  # Runs the block with stdout redirected.
  #
  # @yield the code whose output should be captured
  # @return [String] everything the block wrote to stdout
  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end

RSpec.configure do |config|
  config.include OutputCapture
end
