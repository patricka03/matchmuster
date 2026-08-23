class TeamEntitlement < ApplicationRecord
  PLANS = %w[
    free
    plus
  ].freeze

  STATUSES = %w[
    trialing
    active
    grace_period
    complimentary
    expired
    cancelled
  ].freeze

  PLUS_ACCESS_STATUSES = %w[
    trialing
    active
    grace_period
    complimentary
    cancelled
  ].freeze

  SOURCES = %w[
    standard_trial
    founder
    google_play
    apple
    admin
  ].freeze

  PROVIDERS = %w[
    google_play
    apple
  ].freeze

  BILLING_PERIODS = %w[
    monthly
    annual
  ].freeze

  belongs_to :team

  validates :plan,
            presence: true,
            inclusion: {
              in: PLANS
            }

  validates :status,
            presence: true,
            inclusion: {
              in: STATUSES
            }

  validates :source,
            presence: true,
            inclusion: {
              in: SOURCES
            }

  validates :provider,
            inclusion: {
              in: PROVIDERS
            },
            allow_nil: true

  validates :billing_period,
            inclusion: {
              in: BILLING_PERIODS
            },
            allow_nil: true

  validates :starts_at,
            presence: true

  validates :team_id,
            uniqueness: true

  validates :provider_subscription_id,
            uniqueness: true,
            allow_nil: true

  validates :provider,
            presence: true,
            if: :paid?

  validates :provider_subscription_id,
            presence: true,
            if: :paid?

  validates :provider_product_id,
            presence: true,
            if: :paid?

  validate :paid_entitlement_has_billing_period

  validate :paid_entitlement_provider_matches_source

  validate :google_play_entitlement_has_base_plan

  validate :ends_at_must_be_after_starts_at

  def plus_active?(at: Time.current)
    return false unless plan == "plus"

    return false unless
      PLUS_ACCESS_STATUSES.include?(
        status
      )

    return false if starts_at > at

    return true if ends_at.blank?

    ends_at > at
  end

  def free?(at: Time.current)
    !plus_active?(
      at: at
    )
  end

  def effective_plan(at: Time.current)
    plus_active?(
      at: at
    ) ? "plus" : "free"
  end

  def trialing?
    status == "trialing"
  end

  def cancelled?
    status == "cancelled"
  end

  def grace_period?
    status == "grace_period"
  end

  def founder?
    source == "founder"
  end

  def paid?
    %w[
      google_play
      apple
    ].include?(
      source
    )
  end

  def days_remaining(at: Time.current)
    return nil unless
      plus_active?(
        at: at
      )

    return nil if ends_at.blank?

    seconds_remaining =
      ends_at - at

    (
      seconds_remaining /
      1.day
    ).ceil
  end

  private

  def ends_at_must_be_after_starts_at
    return if
      ends_at.blank? ||
      starts_at.blank?

    return if ends_at > starts_at

    errors.add(
      :ends_at,
      "must be after the entitlement start time"
    )
  end

  def paid_entitlement_has_billing_period
    return unless paid?
    return if billing_period.present?

    errors.add(
      :billing_period,
      "must be present for paid Plus"
    )
  end

  def paid_entitlement_provider_matches_source
    return unless paid?
    return if provider.blank?
    return if provider == source

    errors.add(
      :provider,
      "must match the paid subscription source"
    )
  end

  def google_play_entitlement_has_base_plan
    return unless paid?
    return unless provider == "google_play"
    return if provider_base_plan_id.present?

    errors.add(
      :provider_base_plan_id,
      "must be present for Google Play subscriptions"
    )
  end
end
