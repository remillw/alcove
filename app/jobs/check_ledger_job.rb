# Nightly: every cached balance must equal the sum of its ledger. A drift is a bug, never silently fixed.
class CheckLedgerJob < ApplicationJob
  queue_as :default

  def perform
    drifted = Credits.drifted_user_ids
    Rails.error.report(RuntimeError.new("Credit ledger drift for users #{drifted.inspect}")) if drifted.any?
  end
end
