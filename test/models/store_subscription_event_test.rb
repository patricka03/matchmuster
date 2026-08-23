require "test_helper"

class StoreSubscriptionEventTest < ActiveSupport::TestCase
  setup do
    @team =
      Team.create!(
        name: "Store Event Test FC"
      )

    @occurred_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "valid store event is accepted" do
    event =
      StoreSubscriptionEvent.new(
        valid_attributes
      )

    assert(
      event.valid?,
      event.errors.full_messages.to_sentence
    )

    assert event.pending?

    assert_equal(
      "pending",
      event.processing_status
    )
  end

  test "event can be recorded before its team is resolved" do
    event =
      StoreSubscriptionEvent.new(
        valid_attributes.merge(
          team: nil
        )
      )

    assert(
      event.valid?,
      event.errors.full_messages.to_sentence
    )

    assert_nil event.team
  end

  test "provider must be supported" do
    event =
      StoreSubscriptionEvent.new(
        valid_attributes.merge(
          provider: "fake_store"
        )
      )

    assert_not event.valid?

    assert_includes(
      event.errors[:provider],
      "is not included in the list"
    )
  end

  test "environment must be supported" do
    event =
      StoreSubscriptionEvent.new(
        valid_attributes.merge(
          environment: "testing"
        )
      )

    assert_not event.valid?

    assert_includes(
      event.errors[:environment],
      "is not included in the list"
    )
  end

  test "provider event identifier is unique within provider" do
    StoreSubscriptionEvent.create!(
      valid_attributes
    )

    duplicate =
      StoreSubscriptionEvent.new(
        valid_attributes
      )

    assert_not duplicate.valid?

    assert_includes(
      duplicate.errors[
        :provider_event_id
      ],
      "has already been taken"
    )

    apple_event =
      StoreSubscriptionEvent.new(
        valid_attributes.merge(
          provider: "apple"
        )
      )

    assert(
      apple_event.valid?,
      apple_event.errors.full_messages.to_sentence
    )
  end

  test "metadata must be a JSON object" do
    event =
      StoreSubscriptionEvent.new(
        valid_attributes.merge(
          metadata: [
            "not",
            "an",
            "object"
          ]
        )
      )

    assert_not event.valid?

    assert_includes(
      event.errors[:metadata],
      "must be a JSON object"
    )
  end

  test "pending scope returns only pending events" do
    pending_event =
      StoreSubscriptionEvent.create!(
        valid_attributes
      )

    processed_event =
      StoreSubscriptionEvent.create!(
        valid_attributes.merge(
          provider_event_id:
            "google-event-processed",
          processing_status:
            "processed",
          processed_at:
            @occurred_at
        )
      )

    assert_includes(
      StoreSubscriptionEvent.pending,
      pending_event
    )

    assert_not_includes(
      StoreSubscriptionEvent.pending,
      processed_event
    )
  end

  test "unresolved scope returns events without a team" do
    unresolved_event =
      StoreSubscriptionEvent.create!(
        valid_attributes.merge(
          team: nil
        )
      )

    resolved_event =
      StoreSubscriptionEvent.create!(
        valid_attributes.merge(
          provider_event_id:
            "google-event-resolved"
        )
      )

    assert_includes(
      StoreSubscriptionEvent.unresolved,
      unresolved_event
    )

    assert_not_includes(
      StoreSubscriptionEvent.unresolved,
      resolved_event
    )
  end

  test "event can move from pending to processed" do
    event =
      StoreSubscriptionEvent.create!(
        valid_attributes
      )

    event.mark_processing!

    assert_equal(
      "processing",
      event.processing_status
    )

    processed_at =
      Time.zone.parse(
        "2026-09-01 12:05:00"
      )

    event.mark_processed!(
      at: processed_at
    )

    assert event.processed?

    assert_equal(
      processed_at,
      event.processed_at
    )

    assert_nil(
      event.processing_error
    )
  end

  test "event can record a processing failure" do
    event =
      StoreSubscriptionEvent.create!(
        valid_attributes
      )

    failed_at =
      Time.zone.parse(
        "2026-09-01 12:10:00"
      )

    event.mark_failed!(
      error:
        RuntimeError.new(
          "Store API unavailable"
        ),
      at: failed_at
    )

    assert event.failed?

    assert_equal(
      failed_at,
      event.processed_at
    )

    assert_equal(
      "Store API unavailable",
      event.processing_error
    )
  end

  test "event can be deliberately ignored" do
    event =
      StoreSubscriptionEvent.create!(
        valid_attributes
      )

    ignored_at =
      Time.zone.parse(
        "2026-09-01 12:15:00"
      )

    event.mark_ignored!(
      reason:
        "Test notification",
      at: ignored_at
    )

    assert event.ignored?

    assert_equal(
      ignored_at,
      event.processed_at
    )

    assert_equal(
      "Test notification",
      event.processing_error
    )
  end

  private

  def valid_attributes
    {
      team: @team,
      provider: "google_play",
      provider_event_id:
        "google-event-123",
      event_type:
        "subscription_renewed",
      environment: "sandbox",
      provider_subscription_id:
        "google-subscription-123",
      occurred_at: @occurred_at,
      metadata: {
        "notification_type" =>
          "SUBSCRIPTION_RENEWED"
      }
    }
  end
end
