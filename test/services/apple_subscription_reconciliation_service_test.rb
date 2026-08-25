require "test_helper"

class AppleSubscriptionReconciliationServiceTest <
  ActiveSupport::TestCase

  class FakeApiClient
    attr_accessor :response,
                  :error

    attr_reader :calls

    def initialize(
      response: nil,
      error: nil
    )
      @response = response
      @error = error
      @calls = []
    end

    def fetch_subscription_status(
      original_transaction_id:
    )
      calls <<
        original_transaction_id

      raise error if error

      response.deep_dup
    end
  end

  class FakeSignedDataVerifier
    attr_reader :transaction_calls,
                :renewal_calls

    def initialize(
      transaction:,
      renewal_info:,
      transaction_error: nil,
      renewal_error: nil
    )
      @transaction = transaction
      @renewal_info = renewal_info
      @transaction_error =
        transaction_error
      @renewal_error =
        renewal_error
      @transaction_calls = []
      @renewal_calls = []
    end

    def verify_transaction(value)
      transaction_calls <<
        value

      raise @transaction_error if
        @transaction_error

      @transaction.deep_dup
    end

    def verify_renewal_info(value)
      renewal_calls <<
        value

      raise @renewal_error if
        @renewal_error

      @renewal_info.deep_dup
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
          "Apple Reconciliation FC"
      )

    @subscription_id =
      "apple-original-transaction"

    @entitlement =
      TeamEntitlementService.activate_paid_plus!(
        team: @team,
        provider: "apple",
        provider_subscription_id:
          @subscription_id,
        billing_period: "monthly",
        provider_product_id:
          "matchmuster_plus_monthly",
        starts_at: @starts_at,
        ends_at: @old_ends_at,
        auto_renews: true
      )

    @entitlement.update!(
      last_store_event_at:
        @now - 1.day
    )
  end

  test "active Apple status renews entitlement" do
    event =
      reconcile(
        status: 1
      )

    entitlement =
      @entitlement.reload

    assert event.processed?

    assert_equal(
      "subscription_renewed",
      event.event_type
    )

    assert_equal(
      @team.id,
      event.team_id
    )

    assert_equal(
      "active",
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

    assert_equal(
      @now,
      entitlement.last_store_event_at
    )
  end

  test "disabled renewal becomes cancelled access" do
    event =
      reconcile(
        status: 1,
        auto_renews: false
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

  test "billing grace period retains temporary access" do
    grace_ends_at =
      @new_ends_at + 3.days

    event =
      reconcile(
        status: 4,
        grace_ends_at:
          grace_ends_at
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
      grace_ends_at,
      entitlement.ends_at
    )
  end

  test "billing retry without grace removes access" do
    event =
      reconcile(
        status: 3
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
  end

  test "expired Apple status removes access" do
    event =
      reconcile(
        status: 2
      )

    assert_equal(
      "subscription_expired",
      event.event_type
    )

    assert_equal(
      "free",
      @entitlement.reload.plan
    )
  end

  test "revoked Apple status removes access" do
    event =
      reconcile(
        status: 5
      )

    assert_equal(
      "subscription_revoked",
      event.event_type
    )

    assert_equal(
      "expired",
      @entitlement.reload.status
    )
  end

  test "identical Apple status snapshot is idempotent" do
    api_client =
      FakeApiClient.new(
        response:
          status_response(
            status: 1
          )
      )

    verifier =
      fake_verifier

    first_event = nil
    second_event = nil

    assert_difference(
      "StoreSubscriptionEvent.count",
      1
    ) do
      first_event =
        call_service(
          api_client: api_client,
          verifier: verifier
        )

      second_event =
        call_service(
          api_client: api_client,
          verifier: verifier
        )
    end

    assert_equal(
      first_event.id,
      second_event.id
    )

    assert second_event.processed?
  end

  test "Apple account identity mismatch is rejected" do
    another_team =
      Team.create!(
        name:
          "Another Apple Team"
      )

    verifier =
      fake_verifier(
        account_token:
          another_team.billing_account_token
      )

    assert_no_difference(
      "StoreSubscriptionEvent.count"
    ) do
      assert_raises(
        AppleSubscriptionReconciliationService::
          AccountMismatch
      ) do
        call_service(
          api_client:
            FakeApiClient.new(
              response:
                status_response(
                  status: 1
                )
            ),
          verifier: verifier
        )
      end
    end

    assert_equal(
      @old_ends_at,
      @entitlement.reload.ends_at
    )
  end

  test "response without linked subscription is rejected" do
    response =
      status_response(
        status: 1
      )

    response[
      "data"
    ].first[
      "lastTransactions"
    ].first[
      "originalTransactionId"
    ] =
      "another-original-transaction"

    error =
      assert_raises(
        AppleSubscriptionReconciliationService::
          SubscriptionNotFound
      ) do
        call_service(
          api_client:
            FakeApiClient.new(
              response: response
            ),
          verifier:
            fake_verifier
        )
      end

    assert_includes(
      error.message,
      "linked transaction"
    )
  end

  test "non-Apple entitlement is rejected before API call" do
    google_team =
      Team.create!(
        name:
          "Google Only Team"
      )

    google_entitlement =
      TeamEntitlementService.activate_paid_plus!(
        team: google_team,
        provider: "google_play",
        provider_subscription_id:
          "google-only-token",
        billing_period: "monthly",
        provider_product_id:
          "matchmuster_plus",
        provider_base_plan_id:
          "monthly",
        starts_at: @starts_at,
        ends_at: @new_ends_at,
        auto_renews: true
      )

    api_client =
      FakeApiClient.new(
        response:
          status_response(
            status: 1
          )
      )

    assert_raises(
      AppleSubscriptionReconciliationService::
        InvalidEntitlement
    ) do
      AppleSubscriptionReconciliationService.call(
        entitlement:
          google_entitlement,
        api_client: api_client,
        signed_data_verifier:
          fake_verifier,
        checked_at: @now
      )
    end

    assert_empty(
      api_client.calls
    )
  end

  test "Apple API not-found failure is classified" do
    api_client =
      FakeApiClient.new(
        error:
          AppleAppStoreServerApiClient::
            NotFound.new(
              "Apple subscription was not found"
            )
      )

    error =
      assert_raises(
        AppleSubscriptionReconciliationService::
          SubscriptionNotFound
      ) do
        call_service(
          api_client: api_client,
          verifier:
            fake_verifier
        )
      end

    assert_includes(
      error.message,
      "not found"
    )
  end

  test "temporary Apple API failure is classified" do
    api_client =
      FakeApiClient.new(
        error:
          AppleAppStoreServerApiClient::
            RequestFailed.new(
              "Apple API returned HTTP 503"
            )
      )

    error =
      assert_raises(
        AppleSubscriptionReconciliationService::
          TemporaryFailure
      ) do
        call_service(
          api_client: api_client,
          verifier:
            fake_verifier
        )
      end

    assert_includes(
      error.message,
      "503"
    )
  end

  test "invalid signed Apple response is rejected" do
    verifier =
      FakeSignedDataVerifier.new(
        transaction:
          valid_transaction,
        renewal_info:
          valid_renewal_info,
        transaction_error:
          AppleJwsVerifier::
            InvalidSignature.new(
              "Apple signature is invalid"
            )
      )

    error =
      assert_raises(
        AppleSubscriptionReconciliationService::
          InvalidResponse
      ) do
        call_service(
          api_client:
            FakeApiClient.new(
              response:
                status_response(
                  status: 1
                )
            ),
          verifier: verifier
        )
      end

    assert_includes(
      error.message,
      "signature"
    )
  end

  test "invalid reconciliation timestamp is rejected before API call" do
    api_client =
      FakeApiClient.new(
        response:
          status_response(
            status: 1
          )
      )

    error =
      assert_raises(
        ArgumentError
      ) do
        AppleSubscriptionReconciliationService.call(
          entitlement:
            @entitlement,
          api_client: api_client,
          signed_data_verifier:
            fake_verifier,
          checked_at:
            "not-a-time"
        )
      end

    assert_includes(
      error.message,
      "valid timestamp"
    )

    assert_empty(
      api_client.calls
    )
  end

  private

  def reconcile(
    status:,
    auto_renews: true,
    grace_ends_at:
      @new_ends_at + 3.days
  )
    call_service(
      api_client:
        FakeApiClient.new(
          response:
            status_response(
              status: status
            )
        ),
      verifier:
        fake_verifier(
          auto_renews:
            auto_renews,
          grace_ends_at:
            grace_ends_at
        )
    )
  end

  def call_service(
    api_client:,
    verifier:
  )
    AppleSubscriptionReconciliationService.call(
      entitlement:
        @entitlement,
      api_client: api_client,
      signed_data_verifier:
        verifier,
      checked_at: @now
    )
  end

  def status_response(status:)
    {
      "environment" =>
        "Sandbox",
      "bundleId" =>
        "uk.matchmuster.app",
      "data" => [
        {
          "subscriptionGroupIdentifier" =>
            "matchmuster-plus-group",
          "lastTransactions" => [
            {
              "originalTransactionId" =>
                @subscription_id,
              "status" =>
                status,
              "signedTransactionInfo" =>
                "signed-transaction-status",
              "signedRenewalInfo" =>
                "signed-renewal-status"
            }
          ]
        }
      ]
    }
  end

  def fake_verifier(
    account_token:
      @team.billing_account_token,
    auto_renews: true,
    grace_ends_at:
      @new_ends_at + 3.days
  )
    FakeSignedDataVerifier.new(
      transaction:
        valid_transaction(
          account_token:
            account_token
        ),
      renewal_info:
        valid_renewal_info(
          auto_renews:
            auto_renews,
          grace_ends_at:
            grace_ends_at
        )
    )
  end

  def valid_transaction(
    account_token:
      @team.billing_account_token
  )
    {
      "bundleId" =>
        "uk.matchmuster.app",
      "environment" =>
        "Sandbox",
      "transactionId" =>
        "apple-renewal-transaction",
      "originalTransactionId" =>
        @subscription_id,
      "appAccountToken" =>
        account_token,
      "productId" =>
        "matchmuster_plus_monthly",
      "type" =>
        "Auto-Renewable Subscription",
      "purchaseDate" =>
        milliseconds(
          @starts_at
        ),
      "expiresDate" =>
        milliseconds(
          @new_ends_at
        ),
      "signedDate" =>
        milliseconds(
          @now
        )
    }
  end

  def valid_renewal_info(
    auto_renews: true,
    grace_ends_at:
      @new_ends_at + 3.days
  )
    {
      "environment" =>
        "Sandbox",
      "originalTransactionId" =>
        @subscription_id,
      "autoRenewStatus" =>
        auto_renews ? 1 : 0,
      "gracePeriodExpiresDate" =>
        milliseconds(
          grace_ends_at
        )
    }
  end

  def milliseconds(time)
    (
      time.to_f *
      1000
    ).to_i
  end
end
