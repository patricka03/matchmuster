class ScheduleTeamSubscriptionReconciliationJob <
  ApplicationJob

  queue_as :default

  CURRENT_STATUSES = %w[
    active
    grace_period
    cancelled
  ].freeze

  RECENT_EXPIRY_LOOKBACK =
    7.days

  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(
    at: Time.current,
    reconciliation_job:
      ReconcileTeamSubscriptionJob
  )
    reconciliation_time =
      normalize_time!(
        at
      )

    reconciliable_entitlements(
      reconciliation_time
    ).find_each do |entitlement|
      reconciliation_job.perform_later(
        entitlement.id,
        checked_at:
          reconciliation_time
      )
    end
  end

  private

  def reconciliable_entitlements(
    reconciliation_time
  )
    paid =
      TeamEntitlement
        .where(
          source:
            TeamEntitlement::PROVIDERS,
          provider:
            TeamEntitlement::PROVIDERS
        )
        .where
        .not(
          provider_subscription_id: nil
        )

    current =
      paid.where(
        status:
          CURRENT_STATUSES
      )

    recently_expired =
      paid
        .where(
          status: "expired"
        )
        .where
        .not(
          ends_at: nil
        )
        .where(
          "ends_at >= ?",
          reconciliation_time -
            RECENT_EXPIRY_LOOKBACK
        )

    current.or(
      recently_expired
    )
  end

  def normalize_time!(value)
    return value.in_time_zone if
      value.respond_to?(
        :in_time_zone
      ) &&
      !value.is_a?(
        String
      )

    Time.zone.iso8601(
      value.to_s
    )

  rescue ArgumentError,
         TypeError
    raise ArgumentError,
          "Subscription reconciliation schedule time must be a valid timestamp"
  end
end
