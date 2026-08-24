class StoreSubscriptionEventVerificationJob <
  ApplicationJob

  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  retry_on StoreSubscriptionEventVerificationService::
             TemporaryFailure,
           wait: :polynomially_longer,
           attempts: 5

  def perform(
    event_id,
    verifier:
      StoreSubscriptionEventVerifier
  )
    event =
      StoreSubscriptionEvent.find(
        event_id
      )

    return event if
      terminal?(
        event
      )

    verifier.call(
      event: event
    )
  end

  private

  def terminal?(event)
    event.processed? ||
      event.ignored? ||
      event.verification_rejected?
  end
end
