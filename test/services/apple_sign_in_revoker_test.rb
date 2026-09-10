require "test_helper"

class AppleSignInRevokerTest < ActiveSupport::TestCase
  test "exchange and revoke are bound to the same linked Apple identity" do
    identity = SocialIdentity.new(provider: "apple", uid: "expected-uid")
    service = AppleSignInRevoker.new
    calls = []
    service.define_singleton_method(:client_secret) { "test-server-secret" }
    service.define_singleton_method(:request) do |action, params|
      calls << [action, params]
      action == "token" ? { "id_token" => "signed-test", "access_token" => "test-access" } : {}
    end
    original = SocialIdentityVerifier.method(:call)
    SocialIdentityVerifier.define_singleton_method(:call) { |**| { uid: "expected-uid", provider: "apple" } }
    assert service.call(identity: identity, authorization_code: "one-use-code")
    assert_equal %w[token revoke], calls.map(&:first)
    assert_equal "authorization_code", calls.first.last[:grant_type]
    assert_equal "one-use-code", calls.first.last[:code]
    assert_equal "test-access", calls.last.last[:token]
    assert_equal "access_token", calls.last.last[:token_type_hint]
  ensure
    SocialIdentityVerifier.define_singleton_method(:call, original) if original
  end

  test "a code from a different Apple account is never revoked" do
    service = AppleSignInRevoker.new
    service.define_singleton_method(:client_secret) { "test-server-secret" }
    calls = []
    service.define_singleton_method(:request) do |action, _params|
      calls << action
      { "id_token" => "signed-test", "access_token" => "test-access" }
    end
    original = SocialIdentityVerifier.method(:call)
    SocialIdentityVerifier.define_singleton_method(:call) { |**| { uid: "wrong-uid" } }
    assert_raises(AppleSignInRevoker::Error) do
      service.call(identity: SocialIdentity.new(provider: "apple", uid: "expected-uid"), authorization_code: "wrong-code")
    end
    assert_equal ["token"], calls
  ensure
    SocialIdentityVerifier.define_singleton_method(:call, original) if original
  end
end
