require "test_helper"

class StoreSubscriptionAccountTokenTest <
  ActiveSupport::TestCase

  setup do
    @token =
      SecureRandom.uuid
  end

  test "extracts Apple app account token" do
    result =
      extract(
        provider: "apple",
        payload: {
          "appAccountToken" =>
            @token
        }
      )

    assert_equal(
      @token,
      result
    )
  end

  test "extracts Google Play obfuscated account identifier" do
    result =
      extract(
        provider: "google_play",
        payload: {
          "externalAccountIdentifiers" => {
            "obfuscatedExternalAccountId" =>
              @token
          }
        }
      )

    assert_equal(
      @token,
      result
    )
  end

  test "normalizes token to lowercase" do
    result =
      extract(
        provider: "apple",
        payload: {
          "appAccountToken" =>
            @token.upcase
        }
      )

    assert_equal(
      @token,
      result
    )
  end

  test "missing account token returns nil" do
    assert_nil(
      extract(
        provider: "apple",
        payload: {}
      )
    )

    assert_nil(
      extract(
        provider: "google_play",
        payload: {}
      )
    )
  end

  test "invalid account token is rejected" do
    error =
      assert_raises(
        StoreSubscriptionAccountToken::
          InvalidToken
      ) do
        extract(
          provider: "apple",
          payload: {
            "appAccountToken" =>
              "not-a-valid-uuid"
          }
        )
      end

    assert_includes(
      error.message,
      "must be a UUID"
    )
  end

  test "unsupported provider is rejected" do
    error =
      assert_raises(
        StoreSubscriptionAccountToken::
          UnsupportedProvider
      ) do
        extract(
          provider: "stripe",
          payload: {}
        )
      end

    assert_includes(
      error.message,
      "Unsupported subscription provider"
    )
  end

  test "non object payload is rejected" do
    error =
      assert_raises(
        StoreSubscriptionAccountToken::
          InvalidPayload
      ) do
        extract(
          provider: "apple",
          payload:
            "invalid-payload"
        )
      end

    assert_includes(
      error.message,
      "must be an object"
    )
  end

  test "accepts payloads with symbol keys" do
    result =
      extract(
        provider: "google_play",
        payload: {
          externalAccountIdentifiers: {
            obfuscatedExternalAccountId:
              @token
          }
        }
      )

    assert_equal(
      @token,
      result
    )
  end

  private

  def extract(provider:, payload:)
    StoreSubscriptionAccountToken.call(
      provider: provider,
      payload: payload
    )
  end
end
