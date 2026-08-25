require "test_helper"

class TeamSubscriptionRestoreServiceTest <
  ActiveSupport::TestCase

  class FakeClaimService
    attr_reader :calls

    def initialize(
      result: nil,
      error: nil
    )
      @result =
        result

      @error =
        error

      @calls = []
    end

    def call(**arguments)
      calls <<
        arguments

      raise @error if
        @error

      @result
    end
  end

  setup do
    @team =
      Team.create!(
        name:
          "Subscription Restore FC"
      )

    @restored_event =
      Object.new

    @google_service =
      FakeClaimService.new(
        result:
          @restored_event
      )

    @apple_service =
      FakeClaimService.new(
        result:
          @restored_event
      )
  end

  test "restores Google Play purchase" do
    result =
      restore(
        provider:
          "google_play",
        purchase_token:
          "google-restore-purchase-token"
      )

    assert_same(
      @restored_event,
      result
    )

    assert_equal(
      [
        {
          team: @team,
          purchase_token:
            "google-restore-purchase-token"
        }
      ],
      @google_service.calls
    )

    assert_empty(
      @apple_service.calls
    )
  end

  test "restores Apple purchase" do
    result =
      restore(
        provider:
          "apple",
        signed_transaction:
          "signed-apple-restore-transaction"
      )

    assert_same(
      @restored_event,
      result
    )

    assert_equal(
      [
        {
          team: @team,
          signed_transaction:
            "signed-apple-restore-transaction"
        }
      ],
      @apple_service.calls
    )

    assert_empty(
      @google_service.calls
    )
  end

  test "normalizes provider and purchase data" do
    restore(
      provider:
        "  google_play  ",
      purchase_token:
        "  normalized-google-token  "
    )

    assert_equal(
      "normalized-google-token",
      @google_service
        .calls
        .first
        .fetch(
          :purchase_token
        )
    )
  end

  test "rejects unsupported provider" do
    error =
      assert_raises(
        TeamSubscriptionRestoreService::
          UnsupportedProvider
      ) do
        restore(
          provider:
            "stripe"
        )
      end

    assert_includes(
      error.message,
      "Unsupported subscription provider"
    )

    assert_empty(
      @google_service.calls
    )

    assert_empty(
      @apple_service.calls
    )
  end

  test "requires Google Play purchase token" do
    error =
      assert_raises(
        TeamSubscriptionRestoreService::
          MissingPurchaseData
      ) do
        restore(
          provider:
            "google_play",
          purchase_token:
            ""
        )
      end

    assert_includes(
      error.message,
      "Google Play purchase token is required"
    )

    assert_empty(
      @google_service.calls
    )
  end

  test "requires Apple signed transaction" do
    error =
      assert_raises(
        TeamSubscriptionRestoreService::
          MissingPurchaseData
      ) do
        restore(
          provider:
            "apple",
          signed_transaction:
            ""
        )
      end

    assert_includes(
      error.message,
      "Apple signed transaction is required"
    )

    assert_empty(
      @apple_service.calls
    )
  end

  test "requires a team" do
    error =
      assert_raises(
        TeamSubscriptionRestoreService::
          MissingTeam
      ) do
        TeamSubscriptionRestoreService.call(
          team: nil,
          provider:
            "google_play",
          purchase_token:
            "google-token",
          google_play_claim_service:
            @google_service,
          apple_claim_service:
            @apple_service
        )
      end

    assert_includes(
      error.message,
      "Team is required"
    )
  end

  test "does not hide provider claim errors" do
    provider_error =
      GooglePlaySubscriptionPurchaseClaimService::
        AccountMismatch.new(
          "Google purchase belongs to another account"
        )

    failing_service =
      FakeClaimService.new(
        error:
          provider_error
      )

    error =
      assert_raises(
        GooglePlaySubscriptionPurchaseClaimService::
          AccountMismatch
      ) do
        TeamSubscriptionRestoreService.call(
          team: @team,
          provider:
            "google_play",
          purchase_token:
            "mismatched-google-token",
          google_play_claim_service:
            failing_service,
          apple_claim_service:
            @apple_service
        )
      end

    assert_same(
      provider_error,
      error
    )

    assert_equal(
      1,
      failing_service.calls.length
    )
  end

  test "repeated restore delegates safely to idempotent claim service" do
    2.times do
      restore(
        provider:
          "apple",
        signed_transaction:
          "replayed-apple-transaction"
      )
    end

    assert_equal(
      2,
      @apple_service.calls.length
    )

    assert_equal(
      @apple_service.calls.first,
      @apple_service.calls.second
    )
  end

  private

  def restore(
    provider:,
    purchase_token: nil,
    signed_transaction: nil
  )
    TeamSubscriptionRestoreService.call(
      team: @team,
      provider: provider,
      purchase_token:
        purchase_token,
      signed_transaction:
        signed_transaction,
      google_play_claim_service:
        @google_service,
      apple_claim_service:
        @apple_service
    )
  end
end
