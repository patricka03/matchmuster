class ExpireTeamEntitlementsJob <
  ApplicationJob

  queue_as :default

  EXPIRABLE_STATUSES = %w[
    trialing
    active
    grace_period
    complimentary
    cancelled
  ].freeze

  retry_on ActiveRecord::ConnectionNotEstablished,
           ActiveRecord::ConnectionTimeoutError,
           wait: :polynomially_longer,
           attempts: 5

  def perform(at: Time.current)
    expiration_time =
      normalize_time!(
        at
      )

    expirable_entitlements(
      expiration_time
    ).find_each do |entitlement|
      expire_if_due!(
        entitlement,
        expiration_time
      )
    end
  end

  private

  def expirable_entitlements(
    expiration_time
  )
    TeamEntitlement
      .where(
        plan: "plus",
        status:
          EXPIRABLE_STATUSES
      )
      .where
      .not(
        ends_at: nil
      )
      .where(
        "ends_at <= ?",
        expiration_time
      )
  end

  def expire_if_due!(
    entitlement,
    expiration_time
  )
    entitlement.with_lock do
      entitlement.reload

      return unless
        still_due?(
          entitlement,
          expiration_time
        )

      TeamEntitlementService.expire!(
        team:
          entitlement.team
      )
    end
  end

  def still_due?(
    entitlement,
    expiration_time
  )
    entitlement.plan ==
      "plus" &&
      EXPIRABLE_STATUSES.include?(
        entitlement.status
      ) &&
      entitlement.ends_at.present? &&
      entitlement.ends_at <=
        expiration_time
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
          "Entitlement expiry time must be a valid timestamp"
  end
end
