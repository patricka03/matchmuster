require "test_helper"

class StoreSubscriptionTeamResolverTest <
  ActiveSupport::TestCase

  setup do
    @team =
      Team.create!(
        name: "Resolver Test FC"
      )

    @other_team =
      Team.create!(
        name: "Other Resolver FC"
      )

    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @ends_at =
      @starts_at + 30.days

    @event_sequence = 0
  end

  test "activation resolves team from billing account token" do
    event =
      create_event(
        metadata: {
          "billing_account_token" =>
            @team.billing_account_token
        }
      )

    result =
      resolve(
        event
      )

    assert_equal(
      @team,
      result
    )

    assert_equal(
      @team.id,
      event.reload.team_id
    )
  end

  test "activation accepts explicitly attached team" do
    event =
      create_event(
        team: @team
      )

    assert_equal(
      @team,
      resolve(
        event
      )
    )

    assert_equal(
      @team.id,
      event.reload.team_id
    )
  end

  test "renewal resolves existing linked subscription" do
    activate_paid!

    event =
      create_event(
        event_type:
          "subscription_renewed"
      )

    assert_equal(
      @team,
      resolve(
        event
      )
    )

    assert_equal(
      @team.id,
      event.reload.team_id
    )
  end

  test "unresolved activation is rejected" do
    event =
      create_event

    error =
      assert_raises(
        StoreSubscriptionTeamResolver::
          MissingTeam
      ) do
        resolve(
          event
        )
      end

    assert_includes(
      error.message,
      "Could not resolve"
    )

    assert_nil(
      event.reload.team_id
    )
  end

  test "malformed billing account token is rejected" do
    event =
      create_event(
        metadata: {
          "billing_account_token" =>
            "not-a-uuid"
        }
      )

    error =
      assert_raises(
        StoreSubscriptionTeamResolver::
          InvalidAccountToken
      ) do
        resolve(
          event
        )
      end

    assert_includes(
      error.message,
      "must be a UUID"
    )
  end

  test "unknown billing account token is rejected" do
    event =
      create_event(
        metadata: {
          "billing_account_token" =>
            SecureRandom.uuid
        }
      )

    error =
      assert_raises(
        StoreSubscriptionTeamResolver::
          UnknownAccountToken
      ) do
        resolve(
          event
        )
      end

    assert_includes(
      error.message,
      "does not match a team"
    )
  end

  test "attached team cannot conflict with account token team" do
    event =
      create_event(
        team: @other_team,
        metadata: {
          "billing_account_token" =>
            @team.billing_account_token
        }
      )

    assert_raises(
      StoreSubscriptionTeamResolver::
        OwnershipConflict
    ) do
      resolve(
        event
      )
    end

    assert_equal(
      @other_team.id,
      event.reload.team_id
    )
  end

  test "account token cannot conflict with linked subscription" do
    activate_paid!

    event =
      create_event(
        metadata: {
          "billing_account_token" =>
            @other_team.billing_account_token
        }
      )

    assert_raises(
      StoreSubscriptionTeamResolver::
        OwnershipConflict
    ) do
      resolve(
        event
      )
    end

    assert_nil(
      event.reload.team_id
    )
  end

  test "non activation event requires existing subscription link" do
    event =
      create_event(
        event_type:
          "subscription_cancelled",
        metadata: {
          "billing_account_token" =>
            @team.billing_account_token
        }
      )

    assert_raises(
      StoreSubscriptionTeamResolver::
        SubscriptionNotLinked
    ) do
      resolve(
        event
      )
    end

    assert_nil(
      event.reload.team_id
    )
  end

  private

  def resolve(event)
    StoreSubscriptionTeamResolver.call(
      event: event
    )
  end

  def create_event(
    event_type:
      "subscription_activated",
    team: nil,
    subscription_id:
      "resolver-subscription-123",
    metadata: {}
  )
    @event_sequence += 1

    StoreSubscriptionEvent.create!(
      team: team,
      provider: "google_play",
      provider_event_id:
        "resolver-event-#{@event_sequence}",
      event_type: event_type,
      environment: "sandbox",
      provider_subscription_id:
        subscription_id,
      occurred_at: @starts_at,
      metadata: metadata
    )
  end

  def activate_paid!
    TeamEntitlementService.activate_paid_plus!(
      team: @team,
      provider: "google_play",
      provider_subscription_id:
        "resolver-subscription-123",
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
