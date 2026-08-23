require "test_helper"

class PlusAccessTest < ActiveSupport::TestCase
  setup do
    @team =
      Team.create!(
        name:
          "Plus Access Test FC"
      )

    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "free team cannot access plus feature" do
    assert_not(
      PlusAccess.allowed?(
        team: @team,
        feature:
          :manager_centre,
        at: @starts_at
      )
    )
  end

  test "standard trial can access plus feature" do
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @starts_at
    )

    assert(
      PlusAccess.allowed?(
        team: @team,
        feature:
          :manager_centre,
        at:
          @starts_at +
          1.day
      )
    )
  end

  test "expired trial cannot access plus feature" do
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @starts_at
    )

    assert_not(
      PlusAccess.allowed?(
        team: @team,
        feature:
          :automatic_availability_reminders,
        at:
          @starts_at +
          31.days
      )
    )
  end

  test "founder entitlement can access plus feature" do
    TeamEntitlementService.grant_founder_plus!(
      team: @team,
      starts_at: @starts_at
    )

    assert(
      PlusAccess.allowed?(
        team: @team,
        feature:
          :advanced_season_analytics,
        at:
          @starts_at +
          4.weeks
      )
    )
  end

  test "founder entitlement loses plus access after eight weeks" do
    TeamEntitlementService.grant_founder_plus!(
      team: @team,
      starts_at: @starts_at
    )

    assert_not(
      PlusAccess.allowed?(
        team: @team,
        feature:
          :player_reliability,
        at:
          @starts_at +
          8.weeks +
          1.second
      )
    )
  end

  test "locked is inverse of allowed" do
    assert(
      PlusAccess.locked?(
        team: @team,
        feature:
          :recurring_training,
        at: @starts_at
      )
    )
  end

  test "denial payload is frontend friendly" do
    payload =
      PlusAccess.denial_payload(
        feature:
          :manager_centre
      )

    assert_equal(
      "plus_required",
      payload[:code]
    )

    assert_equal(
      "manager_centre",
      payload[:feature]
    )

    assert_equal(
      "Manager Centre",
      payload[:feature_name]
    )

    assert_equal(
      "MatchMuster Plus is required for this feature.",
      payload[:error]
    )
  end

  test "unknown feature raises error" do
    assert_raises(
      PlusAccess::UnknownFeature
    ) do
      PlusAccess.allowed?(
        team: @team,
        feature:
          :made_up_feature,
        at: @starts_at
      )
    end
  end
end
