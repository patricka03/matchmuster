class AppleStoreSubscriptionVerifier
  class << self
    def call(event:)
      new.call(
        event: event
      )
    end
  end

  def initialize(
    signed_data_verifier: nil
  )
    @signed_data_verifier =
      signed_data_verifier
  end

  def call(event:)
    decoded_notification =
      AppleStoreNotificationDecoder.call(
        event: event,
        signed_data_verifier:
          signed_data_verifier!
      )

    AppleSubscriptionStateMapper.call(
      decoded_notification:
        decoded_notification
    )

  rescue AppleStoreNotificationDecoder::
           InvalidNotification,
         AppleSubscriptionStateMapper::
           InvalidPurchase,
         AppleSignedDataVerifier::
           InvalidPayload,
         AppleSignedDataVerifier::
           InvalidAppIdentifier,
         AppleSignedDataVerifier::
           InvalidEnvironment,
         AppleJwsVerifier::
           VerificationError,
         AppleCertificateChainVerifier::
           InvalidCertificate,
         AppleCertificateChainVerifier::
           InvalidCertificatePurpose,
         AppleCertificateChainVerifier::
           UntrustedCertificateChain => error

    raise StoreSubscriptionEventVerificationService::
            RejectedNotification,
          error.message

  rescue AppleSignedDataVerifier::
           ConfigurationError,
         AppleCertificateChainVerifier::
           ConfigurationError => error

    raise StoreSubscriptionEventVerificationService::
            TemporaryFailure,
          error.message

  rescue StoreSubscriptionEventVerificationService::
           VerificationError

    raise

  rescue StandardError => error
    raise StoreSubscriptionEventVerificationService::
            TemporaryFailure,
          "Apple subscription verification failed temporarily: " \
          "#{error.message}"
  end

  private

  attr_reader :signed_data_verifier

  def signed_data_verifier!
    return signed_data_verifier if
      signed_data_verifier

    factory =
      "AppleSignedDataVerifierFactory"
        .constantize

    factory.build

  rescue NameError
    raise StoreSubscriptionEventVerificationService::
            TemporaryFailure,
          "Apple signed-data verifier is not configured"
  end
end
