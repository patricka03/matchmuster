require "test_helper"

class TeamEntitlementBillingTest < ActiveSupport::TestCase
  setup do
    @team =
      Team.create!(
        name: "Billing Validation FC"
      )

    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "valid Google Play entitlement is accepted" do
    entitlement =
      build_entitlement

    assert(
      entitlement.valid?,
      entitlement.errors.full_messages.to_sentence
    )
  end

  test "valid Apple entitlement does not require a base plan" do
    entitlement =
      build_entitlement(
        source: "apple",
        provider: "apple",
        provider_subscription_id:
          "apple-validation-subscription",
        billing_period: "annual",
        provider_product_id:
          "matchmuster_plus_annual",
        provider_base_plan_id: nil
      )

    assert(
      entitlement.valid?,
      entitlement.errors.full_messages.to_sentence
    )
  end

  test "paid entitlement requires a provider" do
    entitlement =
      build_entitlement(
        provider: nil
      )

    assert_not entitlement.valid?

    assert_includes(
      entitlement.errors[:provider],
      "can't be blank"
    )
  end

  test "paid entitlement requires a subscription identifier" do
    entitlement =
      build_entitlement(
        provider_subscription_id: nil
      )

    assert_not entitlement.valid?

    assert_includes(
      entitlement.errors[
        :provider_subscription_id
      ],
      "can't be blank"
    )
  end

  test "paid entitlement requires a billing period" do
    entitlement =
      build_entitlement(
        billing_period: nil
      )

    assert_not entitlement.valid?

    assert_includes(
      entitlement.errors[:billing_period],
      "must be present for paid Plus"
    )
  end

  test "paid entitlement rejects an unsupported billing period" do
    entitlement =
      build_entitlement(
        billing_period: "weekly"
      )

    assert_not entitlement.valid?

    assert_includes(
      entitlement.errors[:billing_period],
      "is not included in the list"
    )
  end

  test "paid entitlement requires a product identifier" do
    entitlement =
      build_entitlement(
        provider_product_id: nil
      )

    assert_not entitlement.valid?

    assert_includes(
      entitlement.errors[
        :provider_product_id
      ],
      "can't be blank"
    )
  end

  test "Google Play entitlement requires a base plan" do
    entitlement =
      build_entitlement(
        provider_base_plan_id: nil
      )

    assert_not entitlement.valid?

    assert_includes(
      entitlement.errors[
        :provider_base_plan_id
      ],
      "must be present for Google Play subscriptions"
    )
  end

  test "paid provider must match the subscription source" do
    entitlement =
      build_entitlement(
        source: "apple",
        provider: "google_play"
      )

    assert_not entitlement.valid?

    assert_includes(
      entitlement.errors[:provider],
      "must match the paid subscription source"
    )
  end

  private

  def build_entitlement(overrides = {})
    attributes = {
      team: @team,
      plan: "plus",
      status: "active",
      source: "google_play",
      provider: "google_play",
      provider_subscription_id:
        "google-validation-subscription",
      billing_period: "monthly",
      provider_product_id:
        "matchmuster_plus",
      provider_base_plan_id:
        "monthly",
      starts_at: @starts_at,
      ends_at:
        @starts_at + 30.days,
      auto_renews: true
    }

    TeamEntitlement.new(
      attributes.merge(overrides)
    )
  end
end
