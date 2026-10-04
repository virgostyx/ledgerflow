# The closing of a year as a person does it, step by step through the services (F10): for the specs of the reopening and of the full run.
module ClosingHelpers
  # Does steps 1, 6, 7, 12, 15, 16 and 17 (and the validation of the entries after 15 and 16), then lets the owner approve. The run, an accountant who prepares
  # and an owner who approves are given; what the books need to be ready (VAT, bank, comments) is the caller's.
  def close_year!(run:, accountant:, owner:)
    perform = lambda do |code|
      result = Closing::PerformStep.call(run: run, code: code, user: accountant)
      raise "#{code}: #{result.message}" if result.failure?
    end
    validate = lambda do
      result = Closing::ValidateEntries.call(run: run, user: accountant)
      raise "validation: #{result.message}" if result.failure?
    end
    %w[preparation fixed_assets accruals revaluation closing_entries].each { |code| perform.(code) }
    validate.()
    perform.("carry_forward")
    validate.()
    perform.("lock_and_bundle")
    approval = Closing::Approve.call(run: run, user: owner, comment: "Approved")
    raise "approval: #{approval.message}" if approval.failure?

    run.reload
  end
end

RSpec.configure { |config| config.include ClosingHelpers }
