require "test_helper"

class TeamEntitlementTest < ActiveSupport::TestCase
  setup do
    @team =
      Team.create!(
        name: "Entitlement Test FC"
      )

    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "standard trial lasts 30 days" do
    entitlement =
      TeamEntitlementService.start_standard_trial!(
        team: @team,
        starts_at: @starts_at
      )

    assert_equal "plus",
                 entitlement.plan

    assert_equal "trialing",
                 entitlement.status

    assert_equal "standard_trial",
                 entitlement.source

    assert_equal @starts_at,
                 entitlement.starts_at

    assert_equal(
      @starts_at + 30.days,
      entitlement.ends_at
    )

    assert_not entitlement.auto_renews
  end

  test "standard trial provides plus during trial period" do
    entitlement =
      TeamEntitlementService.start_standard_trial!(
        team: @team,
        starts_at: @starts_at
      )

    assert entitlement.plus_active?(
      at:
        @starts_at +
        10.days
    )

    assert_equal(
      "plus",
      entitlement.effective_plan(
        at:
          @starts_at +
          10.days
      )
    )
  end

  test "expired standard trial automatically behaves as free" do
    entitlement =
      TeamEntitlementService.start_standard_trial!(
        team: @team,
        starts_at: @starts_at
      )

    after_trial =
      @starts_at +
      30.days +
      1.second

    assert_not entitlement.plus_active?(
      at: after_trial
    )

    assert entitlement.free?(
      at: after_trial
    )

    assert_equal(
      "free",
      entitlement.effective_plan(
        at: after_trial
      )
    )
  end

  test "trial is not active before its start time" do
    entitlement =
      TeamEntitlementService.start_standard_trial!(
        team: @team,
        starts_at: @starts_at
      )

    assert_not entitlement.plus_active?(
      at:
        @starts_at -
        1.second
    )
  end

  test "founder plus lasts eight weeks" do
    entitlement =
      TeamEntitlementService.grant_founder_plus!(
        team: @team,
        starts_at: @starts_at
      )

    assert_equal "plus",
                 entitlement.plan

    assert_equal "complimentary",
                 entitlement.status

    assert_equal "founder",
                 entitlement.source

    assert_equal(
      @starts_at + 8.weeks,
      entitlement.ends_at
    )

    assert entitlement.founder?
  end

  test "founder plus automatically falls back to free after eight weeks" do
    entitlement =
      TeamEntitlementService.grant_founder_plus!(
        team: @team,
        starts_at: @starts_at
      )

    after_founder_access =
      @starts_at +
      8.weeks +
      1.second

    assert_equal(
      "free",
      entitlement.effective_plan(
        at: after_founder_access
      )
    )

    assert_not entitlement.plus_active?(
      at: after_founder_access
    )
  end

  test "team exposes effective plus entitlement" do
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @starts_at
    )

    assert @team.plus?(
      at:
        @starts_at +
        1.day
    )

    assert_equal(
      "plus",
      @team.effective_plan(
        at:
          @starts_at +
          1.day
      )
    )
  end

  test "team automatically becomes free after entitlement ends" do
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @starts_at
    )

    after_trial =
      @starts_at +
      31.days

    assert @team.free?(
      at: after_trial
    )

    assert_equal(
      "free",
      @team.effective_plan(
        at: after_trial
      )
    )
  end

  test "days remaining rounds partial day upward" do
    entitlement =
      TeamEntitlementService.start_standard_trial!(
        team: @team,
        starts_at: @starts_at
      )

    assert_equal(
      30,
      entitlement.days_remaining(
        at: @starts_at
      )
    )

    assert_equal(
      1,
      entitlement.days_remaining(
        at:
          entitlement.ends_at -
          1.hour
      )
    )
  end

  test "team can only have one entitlement" do
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @starts_at
    )

    duplicate =
      TeamEntitlement.new(
        team: @team,
        plan: "plus",
        status: "active",
        source: "admin",
        starts_at: @starts_at
      )

    assert_not duplicate.valid?

    assert_includes(
      duplicate.errors[:team_id],
      "has already been taken"
    )
  end
end
