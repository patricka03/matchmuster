require "test_helper"

class SocialAccountDeletionTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(first_name: "Deletion", last_name: "Test", email: "delete-social@example.com",
      account_type: "player", password: "Password123!", password_confirmation: "Password123!")
    post "/users/sign_in", params: { user: { email: @user.email, password: "Password123!" } }, as: :json
    assert_response :ok
    @headers = { "Authorization" => response.headers.fetch("Authorization") }
  end

  test "password deletion remains available for email accounts" do
    @user.push_devices.create!(token: "local-deletion-device", platform: "ios")
    delete_account(current_password: "Password123!")
    assert_response :ok
    assert @user.reload.deleted?
    assert_empty @user.push_devices
    get "/users/me", headers: @headers, as: :json
    assert_response :unauthorized
  end

  test "wrong password does not delete the account" do
    delete_account(current_password: "incorrect")
    assert_response :unprocessable_entity
    assert_not @user.reload.deleted?
  end

  test "linked Google proof permits deletion without a MatchMuster password" do
    @user.social_identities.create!(provider: "google", uid: "google-member")
    with_verified_identity(provider: "google", uid: "google-member") do
      delete_account(provider: "google", id_token: "test-proof")
    end
    assert_response :ok
    assert @user.reload.deleted?
    assert_empty @user.social_identities
  end

  test "proof for a different social account cannot delete the current account" do
    @user.social_identities.create!(provider: "google", uid: "google-member")
    with_verified_identity(provider: "google", uid: "somebody-else") do
      delete_account(provider: "google", id_token: "test-proof")
    end
    assert_response :unprocessable_entity
    assert_not @user.reload.deleted?
  end

  test "Apple-linked account requires Apple confirmation even with a valid password" do
    @user.social_identities.create!(provider: "apple", uid: "apple-member")
    delete_account(current_password: "Password123!")
    assert_response :unprocessable_entity
    assert_not @user.reload.deleted?
  end

  test "Apple connection is revoked before deleting local account data" do
    identity = @user.social_identities.create!(provider: "apple", uid: "apple-member")
    calls = []
    with_revoker(->(**args) { calls << args; true }) do
      with_verified_identity(provider: "apple", uid: identity.uid) do
        delete_account(provider: "apple", id_token: "test-proof", authorization_code: "test-code")
      end
    end
    assert_response :ok
    assert @user.reload.deleted?
    assert_equal identity.id, calls.first[:identity].id
    assert_equal "test-code", calls.first[:authorization_code]
  end

  test "revocation failure leaves the account and identity intact for retry" do
    identity = @user.social_identities.create!(provider: "apple", uid: "apple-member")
    with_revoker(->(**) { raise AppleSignInRevoker::Error, "Apple temporarily unavailable" }) do
      with_verified_identity(provider: "apple", uid: identity.uid) do
        delete_account(provider: "apple", id_token: "test-proof", authorization_code: "test-code")
      end
    end
    assert_response :unprocessable_entity
    assert_not @user.reload.deleted?
    assert SocialIdentity.exists?(identity.id)
  end

  private

  def delete_account(**proof)
    delete "/users/account", headers: @headers, as: :json, params: proof
  end

  def with_verified_identity(provider:, uid:)
    original = SocialIdentityVerifier.method(:call)
    SocialIdentityVerifier.define_singleton_method(:call) { |**| { provider: provider, uid: uid } }
    yield
  ensure
    SocialIdentityVerifier.define_singleton_method(:call, original)
  end

  def with_revoker(replacement)
    original = AppleSignInRevoker.method(:call)
    AppleSignInRevoker.define_singleton_method(:call, &replacement)
    yield
  ensure
    AppleSignInRevoker.define_singleton_method(:call, original)
  end
end
