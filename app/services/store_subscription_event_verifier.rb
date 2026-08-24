class StoreSubscriptionEventVerifier
  class VerificationRoutingError <
    StandardError
  end

  class UnsupportedProvider <
    VerificationRoutingError
  end

  class VerifierUnavailable <
    VerificationRoutingError
  end

  VERIFIER_CLASS_NAMES = {
    "google_play" =>
      "GooglePlayStoreSubscriptionVerifier",

    "apple" =>
      "AppleStoreSubscriptionVerifier"
  }.freeze

  class << self
    def call(
      event:,
      verifier: nil
    )
      verifier ||=
        verifier_for(
          event.provider
        )

      StoreSubscriptionEventVerificationService.call(
        event: event,
        verifier: verifier
      )
    end

    def verifier_for(provider)
      provider =
        provider.to_s

      class_name =
        VERIFIER_CLASS_NAMES[
          provider
        ]

      unless class_name
        raise UnsupportedProvider,
              "Unsupported subscription provider: #{provider}"
      end

      class_name.constantize

    rescue NameError
      raise VerifierUnavailable,
            "Subscription verifier is unavailable for #{provider}"
    end
  end
end
