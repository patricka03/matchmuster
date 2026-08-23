require "test_helper"

class StoreSubscriptionEventProcessorTest <
  ActiveSupport::TestCase

  setup do
    @team =
      Team.create!(
        name: "Event Processor Test FC"
      )

    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @ends_at =
      @starts_at + 30.days

    @event_sequence = 0
  end

  test "unverified event is rejected without changing entitlement" do
    event =
      create_event(
        event_type:
          "subscription_activated",
        verified: false
      )

    assert_raises(
      StoreSubscriptionEventProcessor::UnverifiedEvent
    ) do
      process(
        event
      )
    end

    assert event.reload.pending?

    assert_not event.failed?

    assert_nil(
      @team.reload.team_entitlement
    )
  end

  test "verified activation replaces trial with paid plus" do
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @starts_at
    )

    event =
      create_event(
        event_type:
          "subscription_activated"
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
      @team.id,
      event.team_id
    )

    assert_equal(
      "plus",
      entitlement.plan
    )

    assert_equal(
      "active",
      entitlement.status
    )

    assert_equal(
      "google_play",
      entitlement.provider
    )

    assert_equal(
      "google-subscription-123",
      entitlement.provider_subscription_id
    )

    assert_equal(
      "monthly",
      entitlement.billing_period
    )

    assert_equal(
      "matchmuster_plus",
      entitlement.provider_product_id
    )

    assert_equal(
      "monthly",
      entitlement.provider_base_plan_id
    )

    assert(
      entitlement.auto_renews
    )
  end

  test "processed event is idempotent" do
    event =
      create_event(
        event_type:
          "subscription_activated"
      )

    process(
      event
    )

    entitlement =
      @team
        .reload
        .team_entitlement

    original_processed_at =
      event.reload.processed_at

    original_entitlement_updated_at =
      entitlement.updated_at

    assert_no_difference(
      "TeamEntitlement.count"
    ) do
      process(
        event
      )
    end

    assert_equal(
      original_processed_at,
      event.reload.processed_at
    )

    assert_equal(
      original_entitlement_updated_at,
      entitlement.reload.updated_at
    )
  end

  test "renewal extends active paid plus" do
    activate_paid!

    renewed_start =
      @ends_at

    renewed_end =
      @ends_at + 30.days

    event =
      create_event(
        event_type:
          "subscription_renewed",
        metadata:
          valid_metadata.merge(
            "starts_at" =>
              renewed_start.iso8601,
            "ends_at" =>
              renewed_end.iso8601
          )
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
      "active",
      entitlement.status
    )

    assert_equal(
      renewed_start,
      entitlement.starts_at
    )

    assert_equal(
      renewed_end,
      entitlement.ends_at
    )
  end

  test "cancellation preserves access until paid through date" do
    activate_paid!

    event =
      create_event(
        event_type:
          "subscription_cancelled",
        metadata: {
          "ends_at" =>
            @ends_at.iso8601
        }
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
      "cancelled",
      entitlement.status
    )

    assert_not(
      entitlement.auto_renews
    )

    assert(
      entitlement.plus_active?(
        at:
          @ends_at - 1.second
      )
    )

    assert(
      entitlement.free?(
        at:
          @ends_at + 1.second
      )
    )
  end

  test "grace-period event temporarily preserves plus" do
    activate_paid!

    grace_end =
      @ends_at + 3.days

    event =
      create_event(
        event_type:
          "subscription_in_grace_period",
        metadata: {
          "ends_at" =>
            grace_end.iso8601
        }
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
      "grace_period",
      entitlement.status
    )

    assert(
      entitlement.plus_active?(
        at:
          @ends_at + 1.day
      )
    )

    assert(
      entitlement.free?(
        at:
          grace_end + 1.second
      )
    )
  end

  test "expired event removes plus access" do
    activate_paid!

    event =
      create_event(
        event_type:
          "subscription_expired",
        metadata: {}
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
      "free",
      entitlement.plan
    )

    assert_equal(
      "expired",
      entitlement.status
    )

    assert(
      entitlement.free?(
        at: @starts_at
      )
    )
  end

  test "revoked event immediately removes plus access" do
    activate_paid!

    event =
      create_event(
        event_type:
          "subscription_revoked",
        metadata: {}
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
      "free",
      entitlement.plan
    )

    assert_equal(
      "expired",
      entitlement.status
    )
  end

  test "unsupported verified event is safely ignored" do
    activate_paid!

    entitlement =
      @team
        .reload
        .team_entitlement

    original_updated_at =
      entitlement.updated_at

    event =
      create_event(
        event_type:
          "subscription_price_changed",
        metadata: {}
      )

    process(
      event
    )

    assert event.reload.ignored?

    assert_includes(
      event.processing_error,
      "Unsupported subscription event type"
    )

    assert_equal(
      original_updated_at,
      entitlement.reload.updated_at
    )
  end

  test "activation without a resolvable team records failure" do
    event =
      create_event(
        event_type:
          "subscription_activated",
        team: nil,
        subscription_id:
          "unknown-subscription"
      )

    assert_raises(
      StoreSubscriptionEventProcessor::MissingTeam
    ) do
      process(
        event
      )
    end

    assert event.reload.failed?

    assert_includes(
      event.processing_error,
      "Could not resolve a MatchMuster team"
    )

    assert_nil event.team
  end

  test "subscription cannot be transferred to another team" do
    other_team =
      Team.create!(
        name: "Other Subscription FC"
      )

    activate_paid!(
      team: other_team
    )

    event =
      create_event(
        event_type:
          "subscription_activated",
        team: @team
      )

    assert_raises(
      StoreSubscriptionEventProcessor::
        SubscriptionOwnershipConflict
    ) do
      process(
        event
      )
    end

    assert event.reload.failed?

    assert_nil(
      @team.reload.team_entitlement
    )

    assert_equal(
      "active",
      other_team
        .reload
        .team_entitlement
        .status
    )
  end

  test "invalid verified metadata rolls back entitlement changes" do
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @starts_at
    )

    event =
      create_event(
        event_type:
          "subscription_activated",
        metadata:
          valid_metadata.merge(
            "auto_renews" =>
              "yes"
          )
      )

    assert_raises(
      StoreSubscriptionEventProcessor::InvalidMetadata
    ) do
      process(
        event
      )
    end

    assert event.reload.failed?

    entitlement =
      @team
        .reload
        .team_entitlement

    assert_equal(
      "trialing",
      entitlement.status
    )

    assert_equal(
      "standard_trial",
      entitlement.source
    )
  end

  test "lifecycle event must match the team's subscription" do
    activate_paid!(
      subscription_id:
        "real-subscription"
    )

    event =
      create_event(
        event_type:
          "subscription_cancelled",
        subscription_id:
          "different-subscription",
        metadata: {
          "ends_at" =>
            @ends_at.iso8601
        }
      )

    assert_raises(
      StoreSubscriptionEventProcessor::
        SubscriptionNotLinked
    ) do
      process(
        event
      )
    end

    assert event.reload.failed?

    entitlement =
      @team
        .reload
        .team_entitlement

    assert_equal(
      "active",
      entitlement.status
    )

    assert(
      entitlement.auto_renews
    )
  end

  test "renewal cannot replace a different subscription" do
    activate_paid!(
      subscription_id:
        "current-subscription"
    )

    event =
      create_event(
        event_type:
          "subscription_renewed",
        subscription_id:
          "different-subscription"
      )

    assert_raises(
      StoreSubscriptionEventProcessor::
        SubscriptionNotLinked
    ) do
      process(
        event
      )
    end

    assert event.reload.failed?

    entitlement =
      @team
        .reload
        .team_entitlement

    assert_equal(
      "current-subscription",
      entitlement.provider_subscription_id
    )

    assert_equal(
      "active",
      entitlement.status
    )

    assert(
      entitlement.auto_renews
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
    team: @team,
    subscription_id:
      "google-subscription-123",
    metadata: valid_metadata,
    verified: true
  )
    @event_sequence += 1

    event =
      StoreSubscriptionEvent.create!(
        team: team,
        provider: "google_play",
        provider_event_id:
          "google-event-#{@event_sequence}",
        event_type: event_type,
        environment: "sandbox",
        provider_subscription_id:
          subscription_id,
        occurred_at: @starts_at,
        metadata: metadata
      )

    if verified
      event.mark_verified!(
        at: @starts_at
      )
    end

    event
  end

  def activate_paid!(
    team: @team,
    subscription_id:
      "google-subscription-123"
  )
    TeamEntitlementService.activate_paid_plus!(
      team: team,
      provider: "google_play",
      provider_subscription_id:
        subscription_id,
      billing_period: "monthly",
      provider_product_id:
        "matchmuster_plus",
      provider_base_plan_id:
        "monthly",
      starts_at: @starts_at,
      ends_at: @ends_at,
      auto_renews: true
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
