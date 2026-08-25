require "test_helper"

class StoreSubscriptionEventOrderingTest <
  ActiveSupport::TestCase

  setup do
    @team =
      Team.create!(
        name:
          "Subscription Ordering FC"
      )

    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @ends_at =
      @starts_at + 30.days

    @event_sequence = 0
  end

  test "activation records latest store event time" do
    event_time =
      @starts_at + 1.minute

    event =
      create_event(
        event_type:
          "subscription_activated",
        occurred_at:
          event_time
      )

    process(
      event
    )

    entitlement =
      @team
        .reload
        .team_entitlement

    assert event.reload.processed?

    assert_equal(
      event_time,
      entitlement.last_store_event_at
    )

    assert_equal(
      "active",
      entitlement.status
    )
  end

  test "older cancellation cannot overwrite newer renewal" do
    activate_paid!

    renewal_time =
      @starts_at + 2.days

    renewed_start =
      @ends_at

    renewed_end =
      @ends_at + 30.days

    renewal =
      create_event(
        event_type:
          "subscription_renewed",
        occurred_at:
          renewal_time,
        metadata:
          valid_metadata.merge(
            "starts_at" =>
              renewed_start.iso8601,
            "ends_at" =>
              renewed_end.iso8601
          )
      )

    process(
      renewal
    )

    cancellation =
      create_event(
        event_type:
          "subscription_cancelled",
        occurred_at:
          @starts_at + 1.day,
        metadata: {
          "ends_at" =>
            @ends_at.iso8601
        }
      )

    process(
      cancellation
    )

    entitlement =
      @team
        .reload
        .team_entitlement

    assert renewal.reload.processed?

    assert cancellation.reload.ignored?

    assert_includes(
      cancellation.processing_error,
      "Ignored stale subscription event"
    )

    assert_equal(
      "active",
      entitlement.status
    )

    assert_equal(
      renewed_end,
      entitlement.ends_at
    )

    assert_equal(
      renewal_time,
      entitlement.last_store_event_at
    )

    assert entitlement.auto_renews
  end

  test "newer cancellation applies after renewal" do
    activate_paid!

    renewal_time =
      @starts_at + 1.day

    renewed_end =
      @ends_at + 30.days

    renewal =
      create_event(
        event_type:
          "subscription_renewed",
        occurred_at:
          renewal_time,
        metadata:
          valid_metadata.merge(
            "starts_at" =>
              @ends_at.iso8601,
            "ends_at" =>
              renewed_end.iso8601
          )
      )

    process(
      renewal
    )

    cancellation_time =
      renewal_time + 1.day

    cancellation =
      create_event(
        event_type:
          "subscription_cancelled",
        occurred_at:
          cancellation_time,
        metadata: {
          "ends_at" =>
            renewed_end.iso8601
        }
      )

    process(
      cancellation
    )

    entitlement =
      @team
        .reload
        .team_entitlement

    assert cancellation.reload.processed?

    assert_equal(
      "cancelled",
      entitlement.status
    )

    assert_not(
      entitlement.auto_renews
    )

    assert_equal(
      renewed_end,
      entitlement.ends_at
    )

    assert_equal(
      cancellation_time,
      entitlement.last_store_event_at
    )
  end

  test "event with identical timestamp is ignored" do
    event_time =
      @starts_at + 1.hour

    activation =
      create_event(
        event_type:
          "subscription_activated",
        occurred_at:
          event_time
      )

    process(
      activation
    )

    cancellation =
      create_event(
        event_type:
          "subscription_cancelled",
        occurred_at:
          event_time,
        metadata: {
          "ends_at" =>
            @ends_at.iso8601
        }
      )

    process(
      cancellation
    )

    entitlement =
      @team
        .reload
        .team_entitlement

    assert activation.reload.processed?

    assert cancellation.reload.ignored?

    assert_equal(
      "active",
      entitlement.status
    )

    assert entitlement.auto_renews

    assert_equal(
      event_time,
      entitlement.last_store_event_at
    )
  end

  test "supported event without occurred at is rejected" do
    activate_paid!

    event =
      create_event(
        event_type:
          "subscription_cancelled",
        occurred_at: nil,
        metadata: {
          "ends_at" =>
            @ends_at.iso8601
        }
      )

    error =
      assert_raises(
        StoreSubscriptionEventProcessor::
          InvalidMetadata
      ) do
        process(
          event
        )
      end

    assert_includes(
      error.message,
      "occurred_at is missing"
    )

    assert event.reload.failed?

    entitlement =
      @team
        .reload
        .team_entitlement

    assert_equal(
      "active",
      entitlement.status
    )

    assert_nil(
      entitlement.last_store_event_at
    )
  end

  private

  def process(event)
    StoreSubscriptionEventProcessor.call(
      event: event
    )
  end

  def create_event(
    event_type:,
    occurred_at:,
    metadata:
      valid_metadata
  )
    @event_sequence += 1

    event =
      StoreSubscriptionEvent.create!(
        team: @team,
        provider:
          "google_play",
        provider_event_id:
          "ordering-event-#{@event_sequence}",
        event_type:
          event_type,
        environment:
          "sandbox",
        provider_subscription_id:
          "ordering-subscription-123",
        occurred_at:
          occurred_at,
        metadata:
          metadata
      )

    event.mark_verified!(
      at:
        occurred_at ||
          @starts_at
    )

    event
  end

  def activate_paid!
    TeamEntitlementService.activate_paid_plus!(
      team: @team,
      provider:
        "google_play",
      provider_subscription_id:
        "ordering-subscription-123",
      billing_period:
        "monthly",
      provider_product_id:
        "matchmuster_plus",
      provider_base_plan_id:
        "monthly",
      starts_at:
        @starts_at,
      ends_at:
        @ends_at,
      auto_renews:
        true
    )
  end

  def valid_metadata
    {
      "billing_period" =>
        "monthly",

      "product_id" =>
        "matchmuster_plus",

      "base_plan_id" =>
        "monthly",

      "starts_at" =>
        @starts_at.iso8601,

      "ends_at" =>
        @ends_at.iso8601,

      "auto_renews" =>
        true
    }
  end
end
