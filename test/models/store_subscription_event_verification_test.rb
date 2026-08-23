require "test_helper"

class StoreSubscriptionEventVerificationTest <
  ActiveSupport::TestCase

  setup do
    @team =
      Team.create!(
        name:
          "Event Verification Test FC"
      )

    @checked_at =
      Time.zone.parse(
        "2026-09-01 12:30:00"
      )
  end

  test "new event awaits verification" do
    event =
      StoreSubscriptionEvent.create!(
        valid_attributes
      )

    assert(
      event.verification_pending?
    )

    assert_not(
      event.verified?
    )

    assert_nil(
      event.verification_checked_at
    )
  end

  test "event can be marked verified" do
    event =
      StoreSubscriptionEvent.create!(
        valid_attributes
      )

    event.mark_verified!(
      at: @checked_at
    )

    assert event.verified?

    assert_equal(
      @checked_at,
      event.verification_checked_at
    )

    assert_nil(
      event.verification_error
    )
  end

  test "successful verification clears an earlier error" do
    event =
      StoreSubscriptionEvent.create!(
        valid_attributes.merge(
          verification_status:
            "failed",
          verification_error:
            "Temporary store error"
        )
      )

    event.mark_verified!(
      at: @checked_at
    )

    assert event.verified?

    assert_nil(
      event.verification_error
    )
  end

  test "verification failure is recorded" do
    event =
      StoreSubscriptionEvent.create!(
        valid_attributes
      )

    event.mark_verification_failed!(
      error:
        RuntimeError.new(
          "Apple API unavailable"
        ),
      at: @checked_at
    )

    assert(
      event.verification_failed?
    )

    assert_equal(
      @checked_at,
      event.verification_checked_at
    )

    assert_equal(
      "Apple API unavailable",
      event.verification_error
    )
  end

  test "invalid event can be rejected" do
    event =
      StoreSubscriptionEvent.create!(
        valid_attributes
      )

    event.mark_verification_rejected!(
      reason:
        "Invalid signature",
      at: @checked_at
    )

    assert(
      event.verification_rejected?
    )

    assert_equal(
      @checked_at,
      event.verification_checked_at
    )

    assert_equal(
      "Invalid signature",
      event.verification_error
    )
  end

  test "unsupported verification status is rejected" do
    event =
      StoreSubscriptionEvent.new(
        valid_attributes.merge(
          verification_status:
            "trusted"
        )
      )

    assert_not event.valid?

    assert_includes(
      event.errors[
        :verification_status
      ],
      "is not included in the list"
    )
  end

  test "awaiting verification scope only returns pending events" do
    pending_event =
      StoreSubscriptionEvent.create!(
        valid_attributes
      )

    verified_event =
      StoreSubscriptionEvent.create!(
        valid_attributes.merge(
          provider_event_id:
            "apple-event-verified"
        )
      )

    verified_event.mark_verified!(
      at: @checked_at
    )

    assert_includes(
      StoreSubscriptionEvent
        .awaiting_verification,
      pending_event
    )

    assert_not_includes(
      StoreSubscriptionEvent
        .awaiting_verification,
      verified_event
    )
  end

  private

  def valid_attributes
    {
      team: @team,
      provider: "apple",
      provider_event_id:
        "apple-event-123",
      event_type:
        "subscription_renewed",
      environment: "sandbox",
      provider_subscription_id:
        "apple-subscription-123",
      occurred_at:
        @checked_at - 5.minutes,
      metadata: {
        "notification_type" =>
          "DID_RENEW"
      }
    }
  end
end
