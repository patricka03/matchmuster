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

    result =
      AppleSubscriptionStateMapper.call(
        decoded_notification:
          decoded_notification
      )

    attach_account_token(
      result: result,
      payload:
        decoded_notification[
          :transaction
        ]
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
           UntrustedCertificateChain,
         StoreSubscriptionAccountToken::
           InvalidPayload,
         StoreSubscriptionAccountToken::
           InvalidToken => error

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

  def attach_account_token(
    result:,
    payload:
  )
    return result unless
      payload.is_a?(
        Hash
      )

    token =
      StoreSubscriptionAccountToken.call(
        provider: "apple",
        payload: payload
      )

    return result unless token

    result.merge(
      metadata:
        result
          .fetch(
            :metadata
          )
          .merge(
            "billing_account_token" =>
              token
          )
    )
  end
end
