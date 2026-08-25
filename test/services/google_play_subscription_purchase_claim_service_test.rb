require "test_helper"

class GooglePlaySubscriptionPurchaseClaimServiceTest <
  ActiveSupport::TestCase

  class FakeApiClient
    attr_reader :calls

    def initialize(purchase:)
      @purchase =
        purchase

      @calls = []
    end

    def fetch_subscription(
      package_name:,
      purchase_token:
    )
      calls << {
        package_name:
          package_name,
        purchase_token:
          purchase_token
      }

      @purchase.deep_dup
    end
  end

  setup do
    @team =
      Team.create!(
        name: "Google Purchase Claim FC"
      )

    @starts_at =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @ends_at =
      @starts_at + 30.days

    @purchase_token =
      "google-client-purchase-token"
  end

  test "verified purchase claim activates correct team" do
    client =
      fake_client

    event =
      claim(
        client: client
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
      @purchase_token,
      event.provider_subscription_id
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
      "matchmuster_plus",
      entitlement.provider_product_id
    )

    assert_equal(
      "monthly",
      entitlement.provider_base_plan_id
    )

    assert_equal(
      [
        {
          package_name:
            "uk.matchmuster.app",
          purchase_token:
            @purchase_token
        }
      ],
      client.calls
    )
  end

  test "purchase belonging to another account is rejected" do
    purchase =
      valid_purchase

    purchase[
      "externalAccountIdentifiers"
    ][
      "obfuscatedExternalAccountId"
    ] =
      SecureRandom.uuid

    error =
      assert_raises(
        GooglePlaySubscriptionPurchaseClaimService::
          AccountMismatch
      ) do
        claim(
          client:
            fake_client(
              purchase: purchase
            )
        )
      end

    assert_includes(
      error.message,
      "does not belong to this team"
    )

    assert_equal(
      0,
      StoreSubscriptionEvent.count
    )

    assert_nil(
      @team.reload.team_entitlement
    )
  end

  test "purchase without account identity is rejected" do
    purchase =
      valid_purchase

    purchase.delete(
      "externalAccountIdentifiers"
    )

    assert_raises(
      GooglePlaySubscriptionPurchaseClaimService::
        AccountMismatch
    ) do
      claim(
        client:
          fake_client(
            purchase: purchase
          )
      )
    end

    assert_equal(
      0,
      StoreSubscriptionEvent.count
    )

    assert_nil(
      @team.reload.team_entitlement
    )
  end

  test "replayed purchase claim is idempotent" do
    client =
      fake_client

    first_event =
      claim(
        client: client
      )

    second_event = nil

    assert_no_difference(
      "StoreSubscriptionEvent.count"
    ) do
      assert_no_difference(
        "TeamEntitlement.count"
      ) do
        second_event =
          claim(
            client: client
          )
      end
    end

    assert_equal(
      first_event.id,
      second_event.id
    )

    assert_equal(
      1,
      StoreSubscriptionEvent.where(
        provider: "google_play"
      ).count
    )

    assert_equal(
      1,
      TeamEntitlement.where(
        team: @team
      ).count
    )

    assert second_event.reload.processed?
  end

  private

  def claim(client:)
    GooglePlaySubscriptionPurchaseClaimService.call(
      team: @team,
      purchase_token:
        @purchase_token,
      api_client: client,
      package_name:
        "uk.matchmuster.app"
    )
  end

  def fake_client(
    purchase:
      valid_purchase
  )
    FakeApiClient.new(
      purchase: purchase
    )
  end

  def valid_purchase
    {
      "kind" =>
        "androidpublisher#subscriptionPurchaseV2",

      "startTime" =>
        @starts_at.iso8601,

      "subscriptionState" =>
        "SUBSCRIPTION_STATE_ACTIVE",

      "acknowledgementState" =>
        "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",

      "externalAccountIdentifiers" => {
        "obfuscatedExternalAccountId" =>
          @team.billing_account_token
      },

      "lineItems" => [
        {
          "productId" =>
            "matchmuster_plus",

          "expiryTime" =>
            @ends_at.iso8601,

          "latestSuccessfulOrderId" =>
            "GPA.1234-5678-9012-34567",

          "autoRenewingPlan" => {
            "autoRenewEnabled" =>
              true
          },

          "offerDetails" => {
            "basePlanId" =>
              "monthly"
          }
        }
      ]
    }
  end
end
