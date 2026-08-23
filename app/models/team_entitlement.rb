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

  validates :starts_at,
            presence: true

  validates :team_id,
            uniqueness: true

  validates :provider_subscription_id,
            uniqueness: true,
            allow_nil: true

  def plus_active?(at: Time.current)
    return false unless plan == "plus"

    return false unless %w[
      trialing
      active
      grace_period
      complimentary
    ].include?(status)

    return false if starts_at > at

    return true if ends_at.blank?

    ends_at > at
  end

  def free?(at: Time.current)
    !plus_active?(at: at)
  end

  def effective_plan(at: Time.current)
    plus_active?(at: at) ? "plus" : "free"
  end

  def trialing?
    status == "trialing"
  end

  def founder?
    source == "founder"
  end

  def paid?
    %w[
      google_play
      apple
    ].include?(source)
  end

  def days_remaining(at: Time.current)
    return nil unless plus_active?(at: at)
    return nil if ends_at.blank?

    seconds_remaining =
      ends_at - at

    (
      seconds_remaining /
      1.day
    ).ceil
  end
end
