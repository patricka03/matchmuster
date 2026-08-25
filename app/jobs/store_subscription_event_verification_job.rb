class StoreSubscriptionEventVerificationJob < ApplicationJob
  queue_as :default

  discard_on ActiveRecord::RecordNotFound

  retry_on StoreSubscriptionEventVerificationService::TemporaryFailure,
           wait: :polynomially_longer,
           attempts: 5 do |job, error|
    StoreSubscriptionFailureReporter.call(
      job_name: job.class.name,
      record_type: "StoreSubscriptionEvent",
      record_id: job.arguments.first,
      error: error
    )
  end

  def perform(
    event_id,
    verifier: StoreSubscriptionEventVerifier
  )
    event = StoreSubscriptionEvent.find(event_id)

    return event if terminal?(event)

    verifier.call(event: event)
  end

  private

  def terminal?(event)
    event.processed? ||
      event.ignored? ||
      event.verification_rejected?
  end
end
