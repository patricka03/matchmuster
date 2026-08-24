require "openssl"

class AppleCertificateChainVerifier
  class VerificationError < StandardError; end
  class ConfigurationError < VerificationError; end
  class InvalidCertificate < VerificationError; end
  class InvalidCertificatePurpose <
    VerificationError
  end
  class UntrustedCertificateChain <
    VerificationError
  end

  APPLE_LEAF_CERTIFICATE_OID =
    "1.2.840.113635.100.6.11.1"

  APPLE_INTERMEDIATE_CERTIFICATE_OID =
    "1.2.840.113635.100.6.2.1"

  ES256_CURVE =
    "prime256v1"

  def initialize(
    trusted_root_certificates:
  )
    @trusted_root_certificates =
      normalize_trusted_roots!(
        trusted_root_certificates
      )
  end

  def verify(
    leaf_certificate:,
    intermediate_certificate:,
    presented_root_certificate:,
    effective_at:
  )
    leaf_certificate =
      certificate!(
        leaf_certificate,
        description:
          "leaf certificate"
      )

    intermediate_certificate =
      certificate!(
        intermediate_certificate,
        description:
          "intermediate certificate"
      )

    # Apple includes a root in x5c, but it is never
    # trusted merely because the notification supplied it.
    certificate!(
      presented_root_certificate,
      description:
        "presented root certificate"
    )

    validate_leaf_purpose!(
      leaf_certificate
    )

    validate_intermediate_purpose!(
      intermediate_certificate
    )

    validate_leaf_key!(
      leaf_certificate
    )

    verify_trusted_chain!(
      leaf_certificate:
        leaf_certificate,
      intermediate_certificate:
        intermediate_certificate,
      effective_at:
        effective_time!(
          effective_at
        )
    )

    leaf_certificate.public_key
  end

  private

  attr_reader :trusted_root_certificates

  def normalize_trusted_roots!(values)
    values =
      Array(
        values
      )

    if values.empty?
      raise ConfigurationError,
            "Apple trusted root certificates are not configured"
    end

    values.map.with_index do |
      value,
      index
    |
      certificate_from_configuration!(
        value,
        index:
          index
      )
    end
  end

  def certificate_from_configuration!(
    value,
    index:
  )
    return value if
      value.is_a?(
        OpenSSL::X509::Certificate
      )

    OpenSSL::X509::Certificate.new(
      value.to_s
    )

  rescue OpenSSL::X509::CertificateError,
         ArgumentError => error

    raise ConfigurationError,
          "Apple trusted root certificate " \
          "#{index + 1} is invalid: #{error.message}"
  end

  def certificate!(
    value,
    description:
  )
    return value if
      value.is_a?(
        OpenSSL::X509::Certificate
      )

    raise InvalidCertificate,
          "Apple #{description} is invalid"
  end

  def validate_leaf_purpose!(certificate)
    return if
      certificate_has_oid?(
        certificate,
        APPLE_LEAF_CERTIFICATE_OID
      )

    raise InvalidCertificatePurpose,
          "Apple leaf certificate purpose is invalid"
  end

  def validate_intermediate_purpose!(
    certificate
  )
    return if
      certificate_has_oid?(
        certificate,
        APPLE_INTERMEDIATE_CERTIFICATE_OID
      )

    raise InvalidCertificatePurpose,
          "Apple intermediate certificate purpose is invalid"
  end

  def certificate_has_oid?(
    certificate,
    expected_oid
  )
    certificate.extensions.any? do |
      extension
    |
      extension.oid ==
        expected_oid
    end
  end

  def validate_leaf_key!(certificate)
    public_key =
      certificate.public_key

    valid =
      public_key.is_a?(
        OpenSSL::PKey::EC
      ) &&
      public_key.group.curve_name ==
        ES256_CURVE

    return if valid

    raise InvalidCertificate,
          "Apple leaf certificate must use the ES256 curve"
  end

  def effective_time!(value)
    unless value.respond_to?(
      :to_time
    )
      raise InvalidCertificate,
            "Apple certificate verification time is invalid"
    end

    value.to_time
  rescue ArgumentError,
         TypeError

    raise InvalidCertificate,
          "Apple certificate verification time is invalid"
  end

  def verify_trusted_chain!(
    leaf_certificate:,
    intermediate_certificate:,
    effective_at:
  )
    store =
      OpenSSL::X509::Store.new

    trusted_root_certificates.each do |
      certificate
    |
      store.add_cert(
        certificate
      )
    end

    store.time =
      effective_at

    verified =
      store.verify(
        leaf_certificate,
        [
          intermediate_certificate
        ]
      )

    return if verified

    raise UntrustedCertificateChain,
          "Apple certificate chain is not trusted: " \
          "#{store.error_string}"

  rescue OpenSSL::X509::StoreError => error
    raise UntrustedCertificateChain,
          "Apple certificate chain could not be verified: " \
          "#{error.message}"
  end
end
