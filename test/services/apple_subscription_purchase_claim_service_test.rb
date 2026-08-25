require "test_helper"

class AppleSubscriptionPurchaseClaimServiceTest <
  ActiveSupport::TestCase

  class FakeSignedDataVerifier
    attr_reader :calls

    def initialize(
      transaction:,
      error: nil
    )
      @transaction =
        transaction

      @error =
        error

      @calls = []
    end

    def verify_transaction(
      signed_transaction
    )
      calls <<
        signed_transaction

      raise @error if
        @error

      @transaction.deep_dup
    end
  end

  setup do
    @team =
      Team.create!(
        name:
          "Apple Purchase Claim FC"
      )

    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    @starts_at =
      @now - 1.hour

    @ends_at =
      @now + 30.days

    @signed_transaction =
      "signed-apple-client-transaction"
  end

  test "verified Apple purchase activates correct team" do
    verifier =
      fake_verifier

    event = nil

    travel_to(
      @now
    ) do
      event =
        claim(
          verifier: verifier
        )
    end

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
      "apple-original-transaction",
      event.provider_subscription_id
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
      "apple",
      entitlement.provider
    )

    assert_equal(
      "monthly",
      entitlement.billing_period
    )

    assert_equal(
      "matchmuster_plus_monthly",
      entitlement.provider_product_id
    )

    assert_nil(
      entitlement.provider_base_plan_id
    )

    assert_equal(
      [
        @signed_transaction
      ],
      verifier.calls
    )
  end

  test "purchase belonging to another account is rejected" do
    transaction =
      valid_transaction

    transaction[
      "appAccountToken"
    ] =
      SecureRandom.uuid

    travel_to(
      @now
    ) do
      error =
        assert_raises(
          AppleSubscriptionPurchaseClaimService::
            AccountMismatch
        ) do
          claim(
            verifier:
              fake_verifier(
                transaction:
                  transaction
              )
          )
        end

      assert_includes(
        error.message,
        "does not belong to this team"
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

  test "purchase without account identity is rejected" do
    transaction =
      valid_transaction

    transaction.delete(
      "appAccountToken"
    )

    travel_to(
      @now
    ) do
      assert_raises(
        AppleSubscriptionPurchaseClaimService::
          AccountMismatch
      ) do
        claim(
          verifier:
            fake_verifier(
              transaction:
                transaction
            )
        )
      end
    end

    assert_equal(
      0,
      StoreSubscriptionEvent.count
    )

    assert_nil(
      @team.reload.team_entitlement
    )
  end

  test "expired purchase is rejected" do
    transaction =
      valid_transaction

    transaction[
      "expiresDate"
    ] =
      milliseconds(
        @now - 1.minute
      )

    travel_to(
      @now
    ) do
      error =
        assert_raises(
          AppleSubscriptionPurchaseClaimService::
            ExpiredPurchase
        ) do
          claim(
            verifier:
              fake_verifier(
                transaction:
                  transaction
              )
          )
        end

      assert_includes(
        error.message,
        "has expired"
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

  test "revoked purchase is rejected" do
    transaction =
      valid_transaction

    transaction[
      "revocationDate"
    ] =
      milliseconds(
        @now - 1.minute
      )

    travel_to(
      @now
    ) do
      error =
        assert_raises(
          AppleSubscriptionPurchaseClaimService::
            RevokedPurchase
        ) do
          claim(
            verifier:
              fake_verifier(
                transaction:
                  transaction
              )
          )
        end

      assert_includes(
        error.message,
        "has been revoked"
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

  test "unknown Apple product is rejected" do
    transaction =
      valid_transaction

    transaction[
      "productId"
    ] =
      "another-application-product"

    travel_to(
      @now
    ) do
      assert_raises(
        AppleSubscriptionStateMapper::
          UnknownProduct
      ) do
        claim(
          verifier:
            fake_verifier(
              transaction:
                transaction
            )
        )
      end
    end

    assert_equal(
      0,
      StoreSubscriptionEvent.count
    )

    assert_nil(
      @team.reload.team_entitlement
    )
  end

  test "missing signed transaction is rejected" do
    verifier =
      fake_verifier

    error =
      assert_raises(
        AppleSubscriptionPurchaseClaimService::
          MissingSignedTransaction
      ) do
        AppleSubscriptionPurchaseClaimService.call(
          team: @team,
          signed_transaction: "",
          signed_data_verifier:
            verifier
        )
      end

    assert_includes(
      error.message,
      "is required"
    )

    assert_empty(
      verifier.calls
    )
  end

  test "replayed Apple purchase claim is idempotent" do
    verifier =
      fake_verifier

    first_event = nil
    second_event = nil

    travel_to(
      @now
    ) do
      first_event =
        claim(
          verifier: verifier
        )

      assert_no_difference(
        "StoreSubscriptionEvent.count"
      ) do
        assert_no_difference(
          "TeamEntitlement.count"
        ) do
          second_event =
            claim(
              verifier: verifier
            )
        end
      end
    end

    assert_equal(
      first_event.id,
      second_event.id
    )

    assert_equal(
      1,
      StoreSubscriptionEvent.where(
        provider: "apple"
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

  def claim(verifier:)
    AppleSubscriptionPurchaseClaimService.call(
      team: @team,
      signed_transaction:
        @signed_transaction,
      signed_data_verifier:
        verifier
    )
  end

  def fake_verifier(
    transaction:
      valid_transaction
  )
    FakeSignedDataVerifier.new(
      transaction:
        transaction
    )
  end

  def valid_transaction
    {
      "bundleId" =>
        "uk.matchmuster.app",

      "environment" =>
        "Sandbox",

      "transactionId" =>
        "apple-transaction-123",

      "originalTransactionId" =>
        "apple-original-transaction",

      "appAccountToken" =>
        @team.billing_account_token,

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
          @ends_at
        ),

      "signedDate" =>
        milliseconds(
          @now
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
