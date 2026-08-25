require "test_helper"

class StoreSubscriptionEventProcessorTeamResolutionTest <
  ActiveSupport::TestCase

  setup do
    @team =
      Team.create!(
        name: "Processor Resolution FC"
      )

    @other_team =
      Team.create!(
        name: "Other Processor Resolution FC"
      )

    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @ends_at =
      @starts_at + 30.days

    @event_sequence = 0
  end

  test "activation resolves team using billing account token" do
    event =
      create_event(
        metadata:
          valid_metadata.merge(
            "billing_account_token" =>
              @team.billing_account_token
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
      @team.id,
      event.team_id
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
      "processor-resolution-subscription",
      entitlement.provider_subscription_id
    )
  end

  test "unknown account token records processing failure" do
    event =
      create_event(
        metadata:
          valid_metadata.merge(
            "billing_account_token" =>
              SecureRandom.uuid
          )
      )

    error =
      assert_raises(
        StoreSubscriptionEventProcessor::
          UnknownAccountToken
      ) do
        process(
          event
        )
      end

    assert_includes(
      error.message,
      "does not match a team"
    )

    assert event.reload.failed?

    assert_nil(
      event.team_id
    )

    assert_includes(
      event.processing_error,
      "does not match a team"
    )
  end

  test "account token cannot transfer existing subscription" do
    activate_other_team!

    event =
      create_event(
        metadata:
          valid_metadata.merge(
            "billing_account_token" =>
              @team.billing_account_token
          )
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
      event.team_id
    )

    assert_nil(
      @team.reload.team_entitlement
    )

    assert_equal(
      "active",
      @other_team
        .reload
        .team_entitlement
        .status
    )
  end

  private

  def process(event)
    StoreSubscriptionEventProcessor.call(
      event: event
    )
  end

  def create_event(metadata:)
    @event_sequence += 1

    event =
      StoreSubscriptionEvent.create!(
        provider: "google_play",
        provider_event_id:
          "processor-resolution-event-#{@event_sequence}",
        event_type:
          "subscription_activated",
        environment: "sandbox",
        provider_subscription_id:
          "processor-resolution-subscription",
        occurred_at: @starts_at,
        metadata: metadata
      )

    event.mark_verified!(
      at: @starts_at
    )

    event
  end

  def activate_other_team!
    TeamEntitlementService.activate_paid_plus!(
      team: @other_team,
      provider: "google_play",
      provider_subscription_id:
        "processor-resolution-subscription",
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
