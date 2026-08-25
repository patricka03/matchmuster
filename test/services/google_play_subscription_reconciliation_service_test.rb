require "test_helper"

class GooglePlaySubscriptionReconciliationServiceTest <
  ActiveSupport::TestCase

  class FakeApiClient
    attr_accessor :purchase,
                  :error

    attr_reader :calls

    def initialize(
      purchase: nil,
      error: nil
    )
      @purchase =
        purchase

      @error =
        error

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

      raise error if error

      purchase.deep_dup
    end
  end

  setup do
    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @starts_at =
      @now - 15.days

    @old_ends_at =
      @now + 15.days

    @new_ends_at =
      @now + 45.days

    @team =
      Team.create!(
        name:
          "Google Reconciliation FC"
      )

    @purchase_token =
      "google-reconciliation-token"

    @entitlement =
      TeamEntitlementService.activate_paid_plus!(
        team: @team,
        provider: "google_play",
        provider_subscription_id:
          @purchase_token,
        billing_period: "monthly",
        provider_product_id:
          "matchmuster_plus",
        provider_base_plan_id:
          "monthly",
        starts_at: @starts_at,
        ends_at: @old_ends_at,
        auto_renews: true
      )

    @entitlement.update!(
      last_store_event_at:
        @now - 1.day
    )
  end

  test "active store snapshot renews entitlement" do
    event =
      reconcile(
        purchase:
          valid_purchase
      )

    entitlement =
      @entitlement.reload

    assert_equal(
      "processed",
      event.processing_status
    )

    assert_equal(
      "subscription_renewed",
      event.event_type
    )

    assert_equal(
      @team.id,
      event.team_id
    )

    assert_equal(
      "plus",
      entitlement.plan
    )

    assert_equal(
      "active",
      entitlement.status
    )

    assert_equal(
      @new_ends_at,
      entitlement.ends_at
    )

    assert_equal(
      @now,
      entitlement.last_store_event_at
    )
  end

  test "cancelled snapshot preserves access until store expiry" do
    event =
      reconcile(
        purchase:
          valid_purchase(
            state:
              "SUBSCRIPTION_STATE_CANCELED",
            auto_renews: false
          )
      )

    entitlement =
      @entitlement.reload

    assert_equal(
      "subscription_cancelled",
      event.event_type
    )

    assert_equal(
      "cancelled",
      entitlement.status
    )

    assert_equal(
      "plus",
      entitlement.plan
    )

    assert_equal(
      @new_ends_at,
      entitlement.ends_at
    )

    assert_not(
      entitlement.auto_renews
    )
  end

  test "grace-period snapshot updates entitlement" do
    event =
      reconcile(
        purchase:
          valid_purchase(
            state:
              "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
            auto_renews: false
          )
      )

    entitlement =
      @entitlement.reload

    assert_equal(
      "subscription_in_grace_period",
      event.event_type
    )

    assert_equal(
      "grace_period",
      entitlement.status
    )

    assert_equal(
      @new_ends_at,
      entitlement.ends_at
    )
  end

  test "expired snapshot removes Plus access" do
    event =
      reconcile(
        purchase:
          valid_purchase(
            state:
              "SUBSCRIPTION_STATE_EXPIRED",
            auto_renews: false,
            ends_at:
              @now - 1.minute
          )
      )

    entitlement =
      @entitlement.reload

    assert_equal(
      "subscription_expired",
      event.event_type
    )

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

  test "identical store snapshot is idempotent" do
    purchase =
      valid_purchase

    first_event = nil
    second_event = nil

    assert_difference(
      "StoreSubscriptionEvent.count",
      1
    ) do
      first_event =
        reconcile(
          purchase: purchase
        )

      second_event =
        reconcile(
          purchase: purchase
        )
    end

    assert_equal(
      first_event.id,
      second_event.id
    )

    assert_equal(
      "processed",
      second_event.processing_status
    )
  end

  test "account identity mismatch is rejected before persistence" do
    another_team =
      Team.create!(
        name:
          "Another Billing Team"
      )

    error = nil

    assert_no_difference(
      "StoreSubscriptionEvent.count"
    ) do
      error =
        assert_raises(
          GooglePlaySubscriptionReconciliationService::
            AccountMismatch
        ) do
          reconcile(
            purchase:
              valid_purchase(
                account_token:
                  another_team.billing_account_token
              )
          )
        end
    end

    assert_includes(
      error.message,
      "does not belong"
    )

    assert_equal(
      @old_ends_at,
      @entitlement.reload.ends_at
    )
  end

  test "non-Google entitlement is rejected without calling API" do
    apple_team =
      Team.create!(
        name:
          "Apple Reconciliation FC"
      )

    apple_entitlement =
      TeamEntitlementService.activate_paid_plus!(
        team: apple_team,
        provider: "apple",
        provider_subscription_id:
          "apple-original-transaction",
        billing_period: "monthly",
        provider_product_id:
          "matchmuster_plus_monthly",
        starts_at: @starts_at,
        ends_at: @new_ends_at,
        auto_renews: true
      )

    client =
      FakeApiClient.new(
        purchase:
          valid_purchase
      )

    assert_raises(
      GooglePlaySubscriptionReconciliationService::
        InvalidEntitlement
    ) do
      GooglePlaySubscriptionReconciliationService.call(
        entitlement:
          apple_entitlement,
        api_client: client,
        package_name:
          "uk.matchmuster.app",
        checked_at: @now
      )
    end

    assert_empty(
      client.calls
    )
  end

  test "missing package configuration is rejected" do
    client =
      FakeApiClient.new(
        purchase:
          valid_purchase
      )

    assert_raises(
      GooglePlaySubscriptionReconciliationService::
        InvalidConfiguration
    ) do
      GooglePlaySubscriptionReconciliationService.call(
        entitlement:
          @entitlement,
        api_client: client,
        package_name: nil,
        checked_at: @now
      )
    end

    assert_empty(
      client.calls
    )
  end

  test "missing Google purchase is classified" do
    client =
      FakeApiClient.new(
        error:
          GooglePlayDeveloperApiClient::
            NotFound.new(
              "Google Play subscription was not found"
            )
      )

    error =
      assert_raises(
        GooglePlaySubscriptionReconciliationService::
          SubscriptionNotFound
      ) do
        call_service(
          client
        )
      end

    assert_includes(
      error.message,
      "not found"
    )

    assert_equal(
      "active",
      @entitlement.reload.status
    )
  end

  test "temporary Google API failure is classified" do
    client =
      FakeApiClient.new(
        error:
          GooglePlayDeveloperApiClient::
            RequestFailed.new(
              "Google Play API returned HTTP 503"
            )
      )

    error =
      assert_raises(
        GooglePlaySubscriptionReconciliationService::
          TemporaryFailure
      ) do
        call_service(
          client
        )
      end

    assert_includes(
      error.message,
      "503"
    )

    assert_equal(
      "active",
      @entitlement.reload.status
    )
  end

  test "invalid reconciliation timestamp is rejected" do
    client =
      FakeApiClient.new(
        purchase:
          valid_purchase
      )

    error =
      assert_raises(
        ArgumentError
      ) do
        GooglePlaySubscriptionReconciliationService.call(
          entitlement:
            @entitlement,
          api_client: client,
          package_name:
            "uk.matchmuster.app",
          checked_at:
            "not-a-time"
        )
      end

    assert_includes(
      error.message,
      "valid timestamp"
    )

    assert_empty(
      client.calls
    )
  end

  private

  def reconcile(purchase:)
    client =
      FakeApiClient.new(
        purchase: purchase
      )

    call_service(
      client
    )
  end

  def call_service(client)
    GooglePlaySubscriptionReconciliationService.call(
      entitlement:
        @entitlement,
      api_client: client,
      package_name:
        "uk.matchmuster.app",
      checked_at: @now
    )
  end

  def valid_purchase(
    state:
      "SUBSCRIPTION_STATE_ACTIVE",
    auto_renews: true,
    ends_at: @new_ends_at,
    account_token:
      @team.billing_account_token
  )
    {
      "kind" =>
        "androidpublisher#subscriptionPurchaseV2",

      "startTime" =>
        @starts_at.iso8601,

      "subscriptionState" =>
        state,

      "acknowledgementState" =>
        "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",

      "externalAccountIdentifiers" => {
        "obfuscatedExternalAccountId" =>
          account_token
      },

      "lineItems" => [
        {
          "productId" =>
            "matchmuster_plus",

          "expiryTime" =>
            ends_at.iso8601,

          "latestSuccessfulOrderId" =>
            "GPA.1234-5678-9012-34567",

          "autoRenewingPlan" => {
            "autoRenewEnabled" =>
              auto_renews
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
