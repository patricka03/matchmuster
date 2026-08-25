require "test_helper"

class ExpireTeamEntitlementsJobTest <
  ActiveJob::TestCase

  setup do
    @team_sequence = 0

    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "expires ended standard trial" do
    team =
      create_team(
        "Ended Trial"
      )

    TeamEntitlementService.start_standard_trial!(
      team: team,
      starts_at:
        @now - 31.days
    )

    perform_expiry

    entitlement =
      team
        .reload
        .team_entitlement

    assert_equal(
      "free",
      entitlement.plan
    )

    assert_equal(
      "expired",
      entitlement.status
    )

    assert_not(
      entitlement.auto_renews
    )
  end

  test "expires ended founder access" do
    team =
      create_team(
        "Ended Founder"
      )

    TeamEntitlementService.grant_founder_plus!(
      team: team,
      starts_at:
        @now - 9.weeks
    )

    perform_expiry

    entitlement =
      team
        .reload
        .team_entitlement

    assert_equal(
      "free",
      entitlement.plan
    )

    assert_equal(
      "expired",
      entitlement.status
    )

    assert_equal(
      "founder",
      entitlement.source
    )
  end

  test "expires ended active paid subscription" do
    team =
      create_team(
        "Ended Paid"
      )

    activate_paid!(
      team: team,
      ends_at:
        @now - 1.minute
    )

    perform_expiry

    entitlement =
      team
        .reload
        .team_entitlement

    assert_equal(
      "free",
      entitlement.plan
    )

    assert_equal(
      "expired",
      entitlement.status
    )

    assert_equal(
      "google_play",
      entitlement.provider
    )

    assert_not(
      entitlement.auto_renews
    )
  end

  test "expires cancelled subscription after access ends" do
    team =
      create_team(
        "Ended Cancellation"
      )

    activate_paid!(
      team: team,
      ends_at:
        @now + 30.days
    )

    TeamEntitlementService.cancel_paid_plus!(
      team: team,
      access_until:
        @now - 1.minute
    )

    perform_expiry

    entitlement =
      team
        .reload
        .team_entitlement

    assert_equal(
      "free",
      entitlement.plan
    )

    assert_equal(
      "expired",
      entitlement.status
    )
  end

  test "expires grace period after grace access ends" do
    team =
      create_team(
        "Ended Grace"
      )

    activate_paid!(
      team: team,
      ends_at:
        @now + 30.days
    )

    TeamEntitlementService.start_grace_period!(
      team: team,
      ends_at:
        @now - 1.minute
    )

    perform_expiry

    entitlement =
      team
        .reload
        .team_entitlement

    assert_equal(
      "free",
      entitlement.plan
    )

    assert_equal(
      "expired",
      entitlement.status
    )
  end

  test "does not expire access that has not ended" do
    team =
      create_team(
        "Current Access"
      )

    TeamEntitlementService.start_standard_trial!(
      team: team,
      starts_at:
        @now - 10.days
    )

    entitlement =
      team.team_entitlement

    original_updated_at =
      entitlement.updated_at

    perform_expiry

    entitlement.reload

    assert_equal(
      "plus",
      entitlement.plan
    )

    assert_equal(
      "trialing",
      entitlement.status
    )

    assert_equal(
      original_updated_at,
      entitlement.updated_at
    )
  end

  test "does not expire entitlement without end time" do
    team =
      create_team(
        "Open Ended Access"
      )

    activate_paid!(
      team: team,
      ends_at: nil
    )

    perform_expiry

    entitlement =
      team
        .reload
        .team_entitlement

    assert_equal(
      "plus",
      entitlement.plan
    )

    assert_equal(
      "active",
      entitlement.status
    )
  end

  test "already expired entitlement is unchanged" do
    team =
      create_team(
        "Already Expired"
      )

    TeamEntitlementService.start_standard_trial!(
      team: team,
      starts_at:
        @now - 31.days
    )

    TeamEntitlementService.expire!(
      team: team
    )

    entitlement =
      team
        .reload
        .team_entitlement

    original_updated_at =
      entitlement.updated_at

    perform_expiry

    entitlement.reload

    assert_equal(
      "free",
      entitlement.plan
    )

    assert_equal(
      "expired",
      entitlement.status
    )

    assert_equal(
      original_updated_at,
      entitlement.updated_at
    )
  end

  test "running repeatedly is idempotent" do
    team =
      create_team(
        "Repeated Expiry"
      )

    TeamEntitlementService.start_standard_trial!(
      team: team,
      starts_at:
        @now - 31.days
    )

    ExpireTeamEntitlementsJob.perform_now(
      at: @now
    )

    entitlement =
      team
        .reload
        .team_entitlement

    first_updated_at =
      entitlement.updated_at

    assert_no_difference(
      "TeamEntitlement.count"
    ) do
      ExpireTeamEntitlementsJob.perform_now(
        at: @now
      )
    end

    assert_equal(
      first_updated_at,
      entitlement.reload.updated_at
    )

    assert_equal(
      "expired",
      entitlement.status
    )
  end

  test "expires multiple due entitlements in one run" do
    trial_team =
      create_team(
        "Multiple Trial"
      )

    founder_team =
      create_team(
        "Multiple Founder"
      )

    active_team =
      create_team(
        "Multiple Paid"
      )

    TeamEntitlementService.start_standard_trial!(
      team: trial_team,
      starts_at:
        @now - 31.days
    )

    TeamEntitlementService.grant_founder_plus!(
      team: founder_team,
      starts_at:
        @now - 9.weeks
    )

    activate_paid!(
      team: active_team,
      ends_at:
        @now - 1.minute
    )

    perform_expiry

    [
      trial_team,
      founder_team,
      active_team
    ].each do |team|
      entitlement =
        team
          .reload
          .team_entitlement

      assert_equal(
        "free",
        entitlement.plan
      )

      assert_equal(
        "expired",
        entitlement.status
      )
    end
  end

  test "rejects invalid expiry timestamp" do
    error =
      assert_raises(
        ArgumentError
      ) do
        ExpireTeamEntitlementsJob.perform_now(
          at:
            "not-a-time"
        )
      end

    assert_includes(
      error.message,
      "valid timestamp"
    )
  end

  private

  def perform_expiry
    ExpireTeamEntitlementsJob.perform_now(
      at: @now
    )
  end

  def create_team(label)
    @team_sequence += 1

    Team.create!(
      name:
        "#{label} #{@team_sequence}"
    )
  end

  def activate_paid!(
    team:,
    ends_at:
  )
    TeamEntitlementService.activate_paid_plus!(
      team: team,
      provider:
        "google_play",
      provider_subscription_id:
        "expiry-subscription-#{team.id}",
      billing_period:
        "monthly",
      provider_product_id:
        "matchmuster_plus",
      provider_base_plan_id:
        "monthly",
      starts_at:
        @now - 30.days,
      ends_at:
        ends_at,
      auto_renews:
        true
    )
  end
end
