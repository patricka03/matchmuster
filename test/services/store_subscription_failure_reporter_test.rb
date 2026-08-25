require "test_helper"
require "stringio"

class StoreSubscriptionFailureReporterTest < ActiveSupport::TestCase
  test "logs useful identifiers without logging exception secrets" do
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)

    StoreSubscriptionFailureReporter.call(
      job_name: "ReconcileTeamSubscriptionJob",
      record_type: "TeamEntitlement",
      record_id: 42,
      error:
        RuntimeError.new(
          "purchase-token-that-must-not-be-logged"
        ),
      logger: logger
    )

    log = output.string

    assert_includes(log, "store_subscription_job_exhausted")
    assert_includes(log, "ReconcileTeamSubscriptionJob")
    assert_includes(log, "TeamEntitlement")
    assert_includes(log, "42")
    assert_includes(log, "RuntimeError")

    refute_includes(
      log,
      "purchase-token-that-must-not-be-logged"
    )
  end
end
