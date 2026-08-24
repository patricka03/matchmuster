require "test_helper"

class StoreSubscriptionEventVerificationJobTest <
  ActiveJob::TestCase

  setup do
    @event_sequence = 0
  end

  test "pending event is sent to provider verifier" do
    event =
      create_event

    captured_event = nil

    verifier =
      verifier_object do |received_event|
        captured_event =
          received_event

        received_event
      end

    perform_job(
      event,
      verifier
    )

    assert_equal(
      event,
      captured_event
    )
  end

  test "failed verification can be retried" do
    event =
      create_event

    event.mark_verification_failed!(
      error:
        "Temporary store failure"
    )

    calls = 0

    verifier =
      verifier_object do |received_event|
        calls += 1
        received_event
      end

    perform_job(
      event,
      verifier
    )

    assert_equal(
      1,
      calls
    )
  end

  test "processed event is skipped" do
    event =
      create_event

    event.mark_processed!

    perform_job(
      event,
      failing_verifier
    )

    assert event.reload.processed?
  end

  test "ignored event is skipped" do
    event =
      create_event

    event.mark_ignored!(
      reason:
        "Unsupported notification"
    )

    perform_job(
      event,
      failing_verifier
    )

    assert event.reload.ignored?
  end

  test "rejected notification is skipped" do
    event =
      create_event

    event.mark_verification_rejected!(
      reason:
        "Invalid signature"
    )

    perform_job(
      event,
      failing_verifier
    )

    assert(
      event.reload.verification_rejected?
    )
  end

  test "missing event is safely discarded" do
    assert_nothing_raised do
      StoreSubscriptionEventVerificationJob
        .perform_now(
          -1
        )
    end
  end

  private

  def perform_job(event, verifier)
    StoreSubscriptionEventVerificationJob
      .new
      .perform(
        event.id,
        verifier: verifier
      )
  end

  def verifier_object(&block)
    verifier =
      Object.new

    verifier.define_singleton_method(
      :call
    ) do |event:|
      block.call(
        event
      )
    end

    verifier
  end

  def failing_verifier
    verifier_object do |_event|
      raise(
        "Terminal event should not be verified"
      )
    end
  end

  def create_event
    @event_sequence += 1

    StoreSubscriptionEvent.create!(
      provider: "google_play",
      provider_event_id:
        "verification-job-event-#{@event_sequence}",
      event_type:
        "notification_received",
      environment: "sandbox",
      metadata: {},
      raw_payload: {
        "message" => {
          "messageId" =>
            "verification-job-message-#{@event_sequence}"
        }
      }
    )
  end
end
