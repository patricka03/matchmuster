require "test_helper"

class TeamEntitlementServiceTest < ActiveSupport::TestCase
  setup do
    @team =
      Team.create!(
        name:
          "Subscription Lifecycle FC"
      )

    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "google play purchase replaces trial with paid plus" do
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @starts_at
    )

    assert_no_difference(
      "TeamEntitlement.count"
    ) do
      TeamEntitlementService.activate_paid_plus!(
        team: @team,
        provider: "google_play",
        provider_subscription_id:
          "google-test-subscription-1",
        billing_period: "monthly",
        provider_product_id:
          "matchmuster_plus",
        provider_base_plan_id:
          "monthly",
        starts_at:
          @starts_at + 5.days,
        ends_at:
          @starts_at + 35.days,
        auto_renews: true
      )
    end

    entitlement =
      @team
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

    assert_equal(
      "google_play",
      entitlement.source
    )

    assert_equal(
      "google_play",
      entitlement.provider
    )

    assert_equal(
      "google-test-subscription-1",
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

    assert(
      entitlement.paid?
    )
  end

  test "apple purchase can activate paid plus" do
    entitlement =
      TeamEntitlementService.activate_paid_plus!(
        team: @team,
        provider: "apple",
        provider_subscription_id:
          "apple-test-subscription-1",
        billing_period: "annual",
        provider_product_id:
          "matchmuster_plus_annual",
        starts_at: @starts_at,
        ends_at:
          @starts_at + 1.year,
        auto_renews: true
      )

    assert_equal(
      "apple",
      entitlement.source
    )

    assert_equal(
      "active",
      entitlement.status
    )

    assert_equal(
      "annual",
      entitlement.billing_period
    )

    assert_equal(
      "matchmuster_plus_annual",
      entitlement.provider_product_id
    )

    assert_nil(
      entitlement.provider_base_plan_id
    )

    assert(
      entitlement.plus_active?(
        at:
          @starts_at +
          6.months
      )
    )
  end

  test "cancelled paid subscription keeps plus until paid through date" do
    paid_until =
      @starts_at +
      30.days

    TeamEntitlementService.activate_paid_plus!(
      team: @team,
      provider: "google_play",
      provider_subscription_id:
        "google-cancelled-subscription",
      billing_period: "monthly",
      provider_product_id:
        "matchmuster_plus",
      provider_base_plan_id:
        "monthly",
      starts_at: @starts_at,
      ends_at: paid_until,
      auto_renews: true
    )

    entitlement =
      TeamEntitlementService.cancel_paid_plus!(
        team: @team,
        access_until: paid_until
      )

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
          paid_until -
          1.hour
      )
    )

    assert_equal(
      "free",
      entitlement.effective_plan(
        at:
          paid_until +
          1.second
      )
    )
  end

  test "grace period temporarily keeps plus active" do
    original_end =
      @starts_at +
      30.days

    grace_end =
      original_end +
      3.days

    TeamEntitlementService.activate_paid_plus!(
      team: @team,
      provider: "google_play",
      provider_subscription_id:
        "google-grace-subscription",
      billing_period: "monthly",
      provider_product_id:
        "matchmuster_plus",
      provider_base_plan_id:
        "monthly",
      starts_at: @starts_at,
      ends_at: original_end,
      auto_renews: true
    )

    entitlement =
      TeamEntitlementService.start_grace_period!(
        team: @team,
        ends_at: grace_end
      )

    assert(
      entitlement.grace_period?
    )

    assert_not(
      entitlement.auto_renews
    )

    assert(
      entitlement.plus_active?(
        at:
          original_end +
          1.day
      )
    )

    assert_equal(
      "free",
      entitlement.effective_plan(
        at:
          grace_end +
          1.second
      )
    )
  end

  test "invalid provider is rejected" do
    assert_raises(
      ArgumentError
    ) do
      TeamEntitlementService.activate_paid_plus!(
        team: @team,
        provider: "fake_store",
        provider_subscription_id:
          "fake-subscription",
        billing_period: "monthly",
        provider_product_id:
          "fake-product",
        starts_at: @starts_at,
        ends_at:
          @starts_at + 30.days
      )
    end
  end

  test "invalid store product is rejected" do
    assert_raises(
      BillingProductCatalog::UnknownProduct
    ) do
      TeamEntitlementService.activate_paid_plus!(
        team: @team,
        provider: "google_play",
        provider_subscription_id:
          "invalid-product-subscription",
        billing_period: "monthly",
        provider_product_id:
          "wrong-product",
        provider_base_plan_id:
          "monthly",
        starts_at: @starts_at,
        ends_at:
          @starts_at + 30.days
      )
    end
  end

  test "entitlement end must be after start" do
    entitlement =
      TeamEntitlement.new(
        team: @team,
        plan: "plus",
        status: "active",
        source: "google_play",
        provider: "google_play",
        provider_subscription_id:
          "invalid-date-subscription",
        billing_period: "monthly",
        provider_product_id:
          "matchmuster_plus",
        provider_base_plan_id:
          "monthly",
        starts_at: @starts_at,
        ends_at:
          @starts_at - 1.day,
        auto_renews: true
      )

    assert_not(
      entitlement.valid?
    )

    assert_includes(
      entitlement.errors[:ends_at],
      "must be after the entitlement start time"
    )
  end
end
