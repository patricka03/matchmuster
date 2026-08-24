require "test_helper"
require "openssl"

class AppleCertificateChainVerifierTest <
    ActiveSupport::TestCase
  setup do
    @effective_at =
      Time.utc(
        2026,
        9,
        1,
        12,
        0,
        0
      )

    @chain =
      create_certificate_chain
  end

  test "trusts valid Apple certificate chain" do
    verifier =
      build_verifier(
        trusted_roots: [
          @chain.fetch(
            :root
          )
        ]
      )

    public_key =
      verifier.verify(
        leaf_certificate:
          @chain.fetch(
            :leaf
          ),
        intermediate_certificate:
          @chain.fetch(
            :intermediate
          ),
        presented_root_certificate:
          @chain.fetch(
            :root
          ),
        effective_at:
          @effective_at
      )

    assert_instance_of(
      OpenSSL::PKey::EC,
      public_key
    )

    assert_equal(
      @chain
        .fetch(
          :leaf
        )
        .public_key
        .public_to_der,
      public_key.public_to_der
    )
  end

  test "requires configured trusted root" do
    error =
      assert_raises(
        AppleCertificateChainVerifier::
          ConfigurationError
      ) do
        build_verifier(
          trusted_roots: []
        )
      end

    assert_includes(
      error.message,
      "not configured"
    )
  end

  test "rejects chain signed by untrusted root" do
    unrelated_chain =
      create_certificate_chain

    verifier =
      build_verifier(
        trusted_roots: [
          unrelated_chain.fetch(
            :root
          )
        ]
      )

    assert_raises(
      AppleCertificateChainVerifier::
        UntrustedCertificateChain
    ) do
      verify_chain(
        verifier,
        @chain
      )
    end
  end

  test "requires Apple leaf certificate purpose" do
    chain =
      create_certificate_chain(
        include_leaf_oid:
          false
      )

    verifier =
      build_verifier(
        trusted_roots: [
          chain.fetch(
            :root
          )
        ]
      )

    error =
      assert_raises(
        AppleCertificateChainVerifier::
          InvalidCertificatePurpose
      ) do
        verify_chain(
          verifier,
          chain
        )
      end

    assert_includes(
      error.message,
      "leaf certificate purpose"
    )
  end

  test "requires Apple intermediate certificate purpose" do
    chain =
      create_certificate_chain(
        include_intermediate_oid:
          false
      )

    verifier =
      build_verifier(
        trusted_roots: [
          chain.fetch(
            :root
          )
        ]
      )

    error =
      assert_raises(
        AppleCertificateChainVerifier::
          InvalidCertificatePurpose
      ) do
        verify_chain(
          verifier,
          chain
        )
      end

    assert_includes(
      error.message,
      "intermediate certificate purpose"
    )
  end

  test "checks certificate validity at signed date" do
    verifier =
      build_verifier(
        trusted_roots: [
          @chain.fetch(
            :root
          )
        ]
      )

    assert_raises(
      AppleCertificateChainVerifier::
        UntrustedCertificateChain
    ) do
      verifier.verify(
        leaf_certificate:
          @chain.fetch(
            :leaf
          ),
        intermediate_certificate:
          @chain.fetch(
            :intermediate
          ),
        presented_root_certificate:
          @chain.fetch(
            :root
          ),
        effective_at:
          @effective_at + 2.years
      )
    end
  end

  test "requires ES256 leaf key" do
    chain =
      create_certificate_chain(
        leaf_key:
          OpenSSL::PKey::RSA.generate(
            2048
          )
      )

    verifier =
      build_verifier(
        trusted_roots: [
          chain.fetch(
            :root
          )
        ]
      )

    error =
      assert_raises(
        AppleCertificateChainVerifier::
          InvalidCertificate
      ) do
        verify_chain(
          verifier,
          chain
        )
      end

    assert_includes(
      error.message,
      "ES256 curve"
    )
  end

  private

  def build_verifier(trusted_roots:)
    AppleCertificateChainVerifier.new(
      trusted_root_certificates:
        trusted_roots
    )
  end

  def verify_chain(verifier, chain)
    verifier.verify(
      leaf_certificate:
        chain.fetch(
          :leaf
        ),
      intermediate_certificate:
        chain.fetch(
          :intermediate
        ),
      presented_root_certificate:
        chain.fetch(
          :root
        ),
      effective_at:
        @effective_at
    )
  end

  def create_certificate_chain(
    include_leaf_oid: true,
    include_intermediate_oid: true,
    leaf_key:
      OpenSSL::PKey::EC.generate(
        "prime256v1"
      )
  )
    root_key =
      OpenSSL::PKey::EC.generate(
        "prime256v1"
      )

    intermediate_key =
      OpenSSL::PKey::EC.generate(
        "prime256v1"
      )

    root =
      create_certificate(
        serial: 1,
        common_name:
          "MatchMuster Test Apple Root",
        key: root_key,
        ca: true
      )

    intermediate =
      create_certificate(
        serial: 2,
        common_name:
          "MatchMuster Test Apple Intermediate",
        key:
          intermediate_key,
        issuer_certificate:
          root,
        issuer_key:
          root_key,
        ca: true,
        apple_oid:
          include_intermediate_oid ?
            AppleCertificateChainVerifier::
              APPLE_INTERMEDIATE_CERTIFICATE_OID :
            nil
      )

    leaf =
      create_certificate(
        serial: 3,
        common_name:
          "MatchMuster Test Apple Leaf",
        key:
          leaf_key,
        issuer_certificate:
          intermediate,
        issuer_key:
          intermediate_key,
        ca: false,
        apple_oid:
          include_leaf_oid ?
            AppleCertificateChainVerifier::
              APPLE_LEAF_CERTIFICATE_OID :
            nil
      )

    {
      root: root,
      intermediate:
        intermediate,
      leaf: leaf
    }
  end

  def create_certificate(
    serial:,
    common_name:,
    key:,
    ca:,
    issuer_certificate: nil,
    issuer_key: nil,
    apple_oid: nil
  )
    certificate =
      OpenSSL::X509::Certificate.new

    certificate.version = 2
    certificate.serial =
      serial

    certificate.subject =
      OpenSSL::X509::Name.parse(
        "/CN=#{common_name}"
      )

    certificate.issuer =
      issuer_certificate ?
        issuer_certificate.subject :
        certificate.subject

    certificate.public_key =
      OpenSSL::PKey.read(
        key.public_to_der
      )

    certificate.not_before =
      @effective_at - 1.day

    certificate.not_after =
      @effective_at + 1.day

    extension_factory =
      OpenSSL::X509::ExtensionFactory.new

    extension_factory
      .subject_certificate =
        certificate

    extension_factory
      .issuer_certificate =
        issuer_certificate ||
        certificate

    certificate.add_extension(
      extension_factory.create_extension(
        "basicConstraints",
        ca ?
          "CA:TRUE" :
          "CA:FALSE",
        true
      )
    )

    certificate.add_extension(
      extension_factory.create_extension(
        "keyUsage",
        ca ?
          "keyCertSign, cRLSign" :
          "digitalSignature",
        true
      )
    )

    certificate.add_extension(
      extension_factory.create_extension(
        "subjectKeyIdentifier",
        "hash",
        false
      )
    )

    if apple_oid
      certificate.add_extension(
        OpenSSL::X509::Extension.new(
          apple_oid,
          OpenSSL::ASN1::Null(
            nil
          ).to_der,
          false
        )
      )
    end

    certificate.sign(
      issuer_key ||
        key,
      OpenSSL::Digest::SHA256.new
    )

    certificate
  end
end
