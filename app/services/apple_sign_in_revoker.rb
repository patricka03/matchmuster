require "net/http"
require "json"
require "jwt"
require "openssl"

class AppleSignInRevoker
  class Error < StandardError; end

  def self.call(identity:, authorization_code:)
    new.call(identity: identity, authorization_code: authorization_code)
  end

  def call(identity:, authorization_code:)
    raise Error, "Please confirm your Apple identity again." if authorization_code.blank?

    credentials = { client_id: client_id, client_secret: client_secret }
    tokens = request("token", credentials.merge(code: authorization_code, grant_type: "authorization_code"))
    verified = SocialIdentityVerifier.call(provider: "apple", id_token: tokens.fetch("id_token"))
    unless verified[:uid] == identity.uid && identity.provider == "apple"
      raise Error, "Please use the Apple account linked to this MatchMuster account."
    end

    request("revoke", credentials.merge(token: tokens.fetch("access_token"), token_type_hint: "access_token"))
    true
  rescue KeyError, OpenSSL::PKey::PKeyError, JWT::EncodeError
    raise Error, "Apple account deletion is not configured correctly. Please try again later."
  rescue Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError
    raise Error, "Apple could not be reached. Your account has not been deleted. Please try again."
  end

  private

  def client_id
    ENV.fetch("APPLE_SIGN_IN_CLIENT_ID", "uk.matchmuster.mobile")
  end

  def client_secret
    now = Time.current.to_i
    key = OpenSSL::PKey::EC.new(ENV.fetch("APPLE_SIGN_IN_PRIVATE_KEY").gsub('\\n', "\n"))
    JWT.encode({ iss: ENV.fetch("APPLE_SIGN_IN_TEAM_ID"), iat: now, exp: now + 300,
      aud: "https://appleid.apple.com", sub: client_id }, key, "ES256",
      { kid: ENV.fetch("APPLE_SIGN_IN_KEY_ID") })
  end

  def request(action, parameters)
    uri = URI("https://appleid.apple.com/auth/#{action}")
    request = Net::HTTP::Post.new(uri)
    request.set_form_data(parameters)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.request(request)
    end
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("Apple account deletion #{action} failed with HTTP #{response.code}")
      raise Error, "Apple could not confirm account deletion. Please confirm with Apple and try again."
    end
    response.body.blank? ? {} : JSON.parse(response.body)
  end
end
