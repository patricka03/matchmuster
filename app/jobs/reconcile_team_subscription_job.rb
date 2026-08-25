class ReconcileTeamSubscriptionJob < ApplicationJob
  queue_as :default

  RECONCILERS = {
    "google_play" => GooglePlaySubscriptionReconciliationService,
    "apple" => AppleSubscriptionReconciliationService
  }.freeze

  discard_on ActiveRecord::RecordNotFound

  discard_on GooglePlaySubscriptionReconciliationService::InvalidEntitlement,
             GooglePlaySubscriptionReconciliationService::AccountMismatch,
             GooglePlaySubscriptionReconciliationService::ExistingReconciliationConflict,
             AppleSubscriptionReconciliationService::InvalidEntitlement,
             AppleSubscriptionReconciliationService::InvalidResponse,
             AppleSubscriptionReconciliationService::AccountMismatch,
             AppleSubscriptionReconciliationService::ExistingReconciliationConflict

  retry_on GooglePlaySubscriptionReconciliationService::TemporaryFailure,
           GooglePlaySubscriptionReconciliationService::InvalidConfiguration,
           AppleSubscriptionReconciliationService::TemporaryFailure,
           AppleSubscriptionReconciliationService::InvalidConfiguration,
           ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5 do |job, error|
    StoreSubscriptionFailureReporter.call(
      job_name: job.class.name,
      record_type: "TeamEntitlement",
      record_id: job.arguments.first,
      error: error
    )
  end

  retry_on GooglePlaySubscriptionReconciliationService::SubscriptionNotFound,
           AppleSubscriptionReconciliationService::SubscriptionNotFound,
           wait: 5.minutes,
           attempts: 3 do |job, error|
    StoreSubscriptionFailureReporter.call(
      job_name: job.class.name,
      record_type: "TeamEntitlement",
      record_id: job.arguments.first,
      error: error
    )
  end

  def perform(
    entitlement_id,
    checked_at: Time.current,
    reconcilers: RECONCILERS
  )
    entitlement = TeamEntitlement.find(entitlement_id)

    return entitlement unless reconciliation_candidate?(entitlement, reconcilers)

    reconciliation_time = normalize_time!(checked_at)
    reconciler = reconcilers.fetch(entitlement.provider)

    reconciler.call(
      entitlement: entitlement,
      checked_at: reconciliation_time
    )
  end

  private

  def reconciliation_candidate?(entitlement, reconcilers)
    entitlement.paid? &&
      entitlement.provider.present? &&
      entitlement.provider_subscription_id.present? &&
      reconcilers.key?(entitlement.provider)
  end

  def normalize_time!(value)
    if value.respond_to?(:in_time_zone) && !value.is_a?(String)
      return value.in_time_zone
    end

    Time.zone.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    raise ArgumentError,
          "Subscription reconciliation time must be a valid timestamp"
  end
end
