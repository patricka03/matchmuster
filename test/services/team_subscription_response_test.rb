require "test_helper"

class TeamSubscriptionResponseTest <
  ActiveSupport::TestCase

  setup do
    @team =
      Team.create!(
        name: "Subscription Response FC"
      )

    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "team without entitlement returns free response" do
    response =
      subscription_response

    assert_equal(
      "free",
      response.fetch(
        :plan
      )
    )

    assert_equal(
      "free",
      response.fetch(
        :status
      )
    )

    assert_equal(
      false,
      response.fetch(
        :plus_active
      )
    )

    assert_nil(
      response[
        :days_remaining
      ]
    )

    assert_nil(
      response[
        :provider
      ]
    )

    assert_nil(
      response[
        :billing_period
      ]
    )
  end

  test "active trial returns Plus response" do
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @now
    )

    response =
      subscription_response

    assert_equal(
      "plus",
      response.fetch(
        :plan
      )
    )

    assert_equal(
      "trialing",
      response.fetch(
        :status
      )
    )

    assert_equal(
      "standard_trial",
      response.fetch(
        :source
      )
    )

    assert_equal(
      true,
      response.fetch(
        :plus_active
      )
    )

    assert_equal(
      30,
      response.fetch(
        :days_remaining
      )
    )

    assert_equal(
      false,
      response.fetch(
        :auto_renews
      )
    )
  end

  test "expired trial returns effective free plan" do
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at:
        @now - 31.days
    )

    response =
      subscription_response

    assert_equal(
      "free",
      response.fetch(
        :plan
      )
    )

    assert_equal(
      "expired",
      response.fetch(
        :status
      )
    )

    assert_equal(
      false,
      response.fetch(
        :plus_active
      )
    )

    assert_nil(
      response[
        :days_remaining
      ]
    )
  end

  test "paid entitlement includes billing identity" do
    activate_paid!

    response =
      subscription_response

    assert_equal(
      "plus",
      response.fetch(
        :plan
      )
    )

    assert_equal(
      "active",
      response.fetch(
        :status
      )
    )

    assert_equal(
      "google_play",
      response.fetch(
        :provider
      )
    )

    assert_equal(
      "monthly",
      response.fetch(
        :billing_period
      )
    )

    assert_equal(
      "matchmuster_plus",
      response.fetch(
        :provider_product_id
      )
    )

    assert_equal(
      "monthly",
      response.fetch(
        :provider_base_plan_id
      )
    )

    assert_equal(
      true,
      response.fetch(
        :auto_renews
      )
    )
  end

  test "cancelled subscription retains Plus until end date" do
    activate_paid!

    TeamEntitlementService.cancel_paid_plus!(
      team: @team,
      access_until:
        @now + 30.days
    )

    response =
      subscription_response(
        at:
          @now + 15.days
      )

    assert_equal(
      "plus",
      response.fetch(
        :plan
      )
    )

    assert_equal(
      "cancelled",
      response.fetch(
        :status
      )
    )

    assert_equal(
      true,
      response.fetch(
        :plus_active
      )
    )

    assert_equal(
      false,
      response.fetch(
        :auto_renews
      )
    )
  end

  test "cancelled subscription becomes free after end date" do
    activate_paid!

    TeamEntitlementService.cancel_paid_plus!(
      team: @team,
      access_until:
        @now + 30.days
    )

    response =
      subscription_response(
        at:
          @now + 31.days
      )

    assert_equal(
      "free",
      response.fetch(
        :plan
      )
    )

    assert_equal(
      "expired",
      response.fetch(
        :status
      )
    )

    assert_equal(
      false,
      response.fetch(
        :plus_active
      )
    )

    assert_nil(
      response[
        :days_remaining
      ]
    )
  end

  private

  def subscription_response(at: @now)
    TeamSubscriptionResponse.call(
      team: @team,
      at: at
    )
  end

  def activate_paid!
    TeamEntitlementService.activate_paid_plus!(
      team: @team,
      provider: "google_play",
      provider_subscription_id:
        "response-subscription-123",
      billing_period: "monthly",
      provider_product_id:
        "matchmuster_plus",
      provider_base_plan_id:
        "monthly",
      starts_at: @now,
      ends_at:
        @now + 30.days,
      auto_renews: true
    )
  end
end
