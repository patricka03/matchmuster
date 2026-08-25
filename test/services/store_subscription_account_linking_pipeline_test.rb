require "test_helper"

class StoreSubscriptionAccountLinkingPipelineTest <
  ActiveSupport::TestCase

  class FakeVerifier
    attr_reader :calls

    def initialize(result:)
      @result =
        result

      @calls = 0
    end

    def call(event:)
      @calls += 1

      @result
    end
  end

  setup do
    @team =
      Team.create!(
        name: "Account Linking Pipeline FC"
      )

    @other_team =
      Team.create!(
        name: "Other Account Linking FC"
      )

    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @ends_at =
      @starts_at + 30.days

    @event_sequence = 0
  end

  test "verified Google purchase activates correct team" do
    event =
      create_event(
        provider: "google_play"
      )

    verifier =
      fake_verifier(
        provider: "google_play",
        team: @team,
        subscription_id:
          "pipeline-google-subscription"
      )

    verify_and_process(
      event: event,
      verifier: verifier
    )

    entitlement =
      @team
        .reload
        .team_entitlement

    assert event.reload.verified?

    assert event.processed?

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
      "pipeline-google-subscription",
      entitlement.provider_subscription_id
    )

    assert_equal(
      "matchmuster_plus",
      entitlement.provider_product_id
    )

    assert_equal(
      "monthly",
      entitlement.provider_base_plan_id
    )
  end

  test "verified Apple purchase activates correct team" do
    event =
      create_event(
        provider: "apple"
      )

    verifier =
      fake_verifier(
        provider: "apple",
        team: @team,
        subscription_id:
          "pipeline-apple-subscription"
      )

    verify_and_process(
      event: event,
      verifier: verifier
    )

    entitlement =
      @team
        .reload
        .team_entitlement

    assert event.reload.verified?

    assert event.processed?

    assert_equal(
      @team.id,
      event.team_id
    )

    assert_equal(
      "active",
      entitlement.status
    )

    assert_equal(
      "apple",
      entitlement.provider
    )

    assert_equal(
      "pipeline-apple-subscription",
      entitlement.provider_subscription_id
    )

    assert_equal(
      "matchmuster_plus_monthly",
      entitlement.provider_product_id
    )

    assert_nil(
      entitlement.provider_base_plan_id
    )
  end

  test "verified token cannot transfer another team's subscription" do
    activate_paid!(
      team: @other_team,
      subscription_id:
        "pipeline-conflict-subscription"
    )

    event =
      create_event(
        provider: "google_play"
      )

    verifier =
      fake_verifier(
        provider: "google_play",
        team: @team,
        subscription_id:
          "pipeline-conflict-subscription"
      )

    assert_raises(
      StoreSubscriptionEventProcessor::
        SubscriptionOwnershipConflict
    ) do
      verify_and_process(
        event: event,
        verifier: verifier
      )
    end

    assert event.reload.verified?

    assert event.failed?

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

  test "processed notification replay is idempotent" do
    event =
      create_event(
        provider: "google_play"
      )

    verifier =
      fake_verifier(
        provider: "google_play",
        team: @team,
        subscription_id:
          "pipeline-replay-subscription"
      )

    verify_and_process(
      event: event,
      verifier: verifier
    )

    original_entitlement =
      @team
        .reload
        .team_entitlement

    original_updated_at =
      original_entitlement.updated_at

    verify_and_process(
      event: event,
      verifier: verifier
    )

    assert_equal(
      1,
      verifier.calls
    )

    assert_equal(
      original_updated_at,
      original_entitlement
        .reload
        .updated_at
    )

    assert_equal(
      1,
      TeamEntitlement.where(
        team: @team
      ).count
    )

    assert event.reload.processed?
  end

  private

  def verify_and_process(
    event:,
    verifier:
  )
    StoreSubscriptionEventVerificationService.call(
      event: event,
      verifier: verifier
    )
  end

  def fake_verifier(
    provider:,
    team:,
    subscription_id:
  )
    FakeVerifier.new(
      result:
        normalized_result(
          provider: provider,
          team: team,
          subscription_id:
            subscription_id
        )
    )
  end

  def normalized_result(
    provider:,
    team:,
    subscription_id:
  )
    apple =
      provider == "apple"

    {
      event_type:
        "subscription_activated",

      environment:
        "sandbox",

      provider_subscription_id:
        subscription_id,

      occurred_at:
        @starts_at,

      metadata: {
        "billing_account_token" =>
          team.billing_account_token,

        "billing_period" =>
          "monthly",

        "product_id" =>
          apple ?
            "matchmuster_plus_monthly" :
            "matchmuster_plus",

        "base_plan_id" =>
          apple ?
            nil :
            "monthly",

        "starts_at" =>
          @starts_at.iso8601,

        "ends_at" =>
          @ends_at.iso8601,

        "auto_renews" =>
          true
      }
    }
  end

  def create_event(provider:)
    @event_sequence += 1

    StoreSubscriptionEvent.create!(
      provider: provider,
      provider_event_id:
        "account-linking-event-#{@event_sequence}",
      event_type:
        "notification_received",
      environment:
        "sandbox",
      metadata: {},
      raw_payload: {
        "notification" =>
          "pipeline-test"
      }
    )
  end

  def activate_paid!(
    team:,
    subscription_id:
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
end
