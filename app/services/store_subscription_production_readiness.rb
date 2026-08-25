require "base64"
require "json"
require "openssl"
require "uri"

class StoreSubscriptionProductionReadiness
  class ConfigurationError < StandardError
    attr_reader :problems

    def initialize(problems)
      @problems = problems.freeze

      super(
        "Subscription production configuration is invalid:\n" +
          problems.map { |problem| "- #{problem}" }.join("\n")
      )
    end
  end

  class << self
    def call(environment: ENV)
      new(environment: environment).call
    end
  end

  def initialize(environment:)
    @environment = environment
    @problems = []
  end

  def call
    validate_frontend_url
    validate_apple_configuration
    validate_google_configuration
    validate_http_timeouts

    raise ConfigurationError, problems if problems.any?

    {
      ok: true,
      apple_environment: value("APPLE_STORE_ENVIRONMENT").downcase,
      google_credentials: google_credentials_source,
      open_timeout_seconds:
        StoreSubscriptionHttpConfiguration.open_timeout(
          environment: environment
        ),
      read_timeout_seconds:
        StoreSubscriptionHttpConfiguration.read_timeout(
          environment: environment
        )
    }
  end

  private

  attr_reader :environment, :problems

  def validate_frontend_url
    raw_url = required("FRONTEND_URL")
    return if raw_url.empty?

    uri = URI.parse(raw_url)

    unless uri.is_a?(URI::HTTPS) && uri.host.present?
      problems << "FRONTEND_URL must be an absolute https URL"
    end
  rescue URI::InvalidURIError
    problems << "FRONTEND_URL must be a valid URL"
  end

  def validate_apple_configuration
    bundle_id = required("APPLE_BUNDLE_ID")
    apple_environment = required("APPLE_STORE_ENVIRONMENT").downcase
    app_id = required("APPLE_APP_ID")
    required("APPLE_ISSUER_ID")
    required("APPLE_KEY_ID")

    unless bundle_id.empty? || bundle_id.match?(/\A[a-zA-Z0-9.-]+\z/)
      problems << "APPLE_BUNDLE_ID has an invalid format"
    end

    unless apple_environment.empty? || %w[sandbox production].include?(apple_environment)
      problems << "APPLE_STORE_ENVIRONMENT must be sandbox or production"
    end

    unless app_id.empty? || app_id.match?(/\A\d+\z/)
      problems << "APPLE_APP_ID must contain digits only"
    end

    validate_apple_private_key
    validate_apple_root_certificates
  end

  def validate_apple_private_key
    private_key = required("APPLE_PRIVATE_KEY")
    return if private_key.empty?

    parsed_key = OpenSSL::PKey.read(
      private_key.gsub("\\n", "\n")
    )

    unless parsed_key.is_a?(OpenSSL::PKey::EC) && parsed_key.private?
      problems << "APPLE_PRIVATE_KEY must be an EC private key"
    end
  rescue OpenSSL::PKey::PKeyError, ArgumentError
    problems << "APPLE_PRIVATE_KEY is invalid"
  end

  def validate_apple_root_certificates
    encoded_certificates =
      required("APPLE_ROOT_CERTIFICATES_BASE64")
        .split(",")
        .map(&:strip)
        .reject(&:empty?)

    return if encoded_certificates.empty?

    encoded_certificates.each_with_index do |encoded_certificate, index|
      certificate_data = Base64.strict_decode64(encoded_certificate)
      OpenSSL::X509::Certificate.new(certificate_data)
    rescue ArgumentError, OpenSSL::X509::CertificateError
      problems << "APPLE_ROOT_CERTIFICATES_BASE64 certificate #{index + 1} is invalid"
    end
  end

  def validate_google_configuration
    required("GOOGLE_PLAY_PACKAGE_NAME")

    json = value("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
    path = value("GOOGLE_APPLICATION_CREDENTIALS")

    if json.empty? && path.empty?
      problems <<
        "Set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON or GOOGLE_APPLICATION_CREDENTIALS"
      return
    end

    validate_google_json(json) unless json.empty?
  end

  def validate_google_json(json)
    credentials = JSON.parse(json)

    unless credentials.is_a?(Hash)
      problems << "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON must contain a JSON object"
      return
    end

    %w[type project_id private_key client_email token_uri].each do |key|
      if credentials[key].to_s.strip.empty?
        problems << "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is missing #{key}"
      end
    end

    if credentials["type"].present? && credentials["type"] != "service_account"
      problems << "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON must be a service account"
    end

    private_key = credentials["private_key"].to_s
    return if private_key.empty?

    parsed_key = OpenSSL::PKey.read(private_key)

    unless parsed_key.private?
      problems << "Google service-account private key is not private"
    end
  rescue JSON::ParserError
    problems << "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is invalid JSON"
  rescue OpenSSL::PKey::PKeyError, ArgumentError
    problems << "Google service-account private key is invalid"
  end

  def validate_http_timeouts
    StoreSubscriptionHttpConfiguration.open_timeout(
      environment: environment
    )

    StoreSubscriptionHttpConfiguration.read_timeout(
      environment: environment
    )
  rescue StoreSubscriptionHttpConfiguration::ConfigurationError => error
    problems << error.message
  end

  def google_credentials_source
    if value("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON").present?
      "environment_json"
    else
      "application_default_credentials"
    end
  end

  def required(key)
    configured_value = value(key)

    problems << "#{key} is missing" if configured_value.empty?
    configured_value
  end

  def value(key)
    environment[key].to_s.strip
  end
end
