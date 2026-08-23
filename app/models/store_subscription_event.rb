class StoreSubscriptionEvent < ApplicationRecord
  PROVIDERS = %w[
    google_play
    apple
  ].freeze

  ENVIRONMENTS = %w[
    sandbox
    production
  ].freeze

  PROCESSING_STATUSES = %w[
    pending
    processing
    processed
    failed
    ignored
  ].freeze

  VERIFICATION_STATUSES = %w[
    pending
    verified
    failed
    rejected
  ].freeze

  belongs_to :team,
             optional: true

  validates :provider,
            presence: true,
            inclusion: {
              in: PROVIDERS
            }

  validates :provider_event_id,
            presence: true,
            uniqueness: {
              scope: :provider
            }

  validates :event_type,
            presence: true

  validates :environment,
            presence: true,
            inclusion: {
              in: ENVIRONMENTS
            }

  validates :processing_status,
            presence: true,
            inclusion: {
              in: PROCESSING_STATUSES
            }

  validates :verification_status,
            presence: true,
            inclusion: {
              in: VERIFICATION_STATUSES
            }

  validate :metadata_must_be_an_object

  scope :pending,
        -> {
          where(
            processing_status: "pending"
          )
        }

  scope :unresolved,
        -> {
          where(
            team_id: nil
          )
        }

  scope :awaiting_verification,
        -> {
          where(
            verification_status: "pending"
          )
        }

  def pending?
    processing_status == "pending"
  end

  def processed?
    processing_status == "processed"
  end

  def failed?
    processing_status == "failed"
  end

  def ignored?
    processing_status == "ignored"
  end

  def verification_pending?
    verification_status == "pending"
  end

  def verified?
    verification_status == "verified"
  end

  def verification_failed?
    verification_status == "failed"
  end

  def verification_rejected?
    verification_status == "rejected"
  end

  def mark_processing!
    update!(
      processing_status: "processing",
      processing_error: nil
    )
  end

  def mark_processed!(at: Time.current)
    update!(
      processing_status: "processed",
      processed_at: at,
      processing_error: nil
    )
  end

  def mark_failed!(error:, at: Time.current)
    update!(
      processing_status: "failed",
      processed_at: at,
      processing_error: error.to_s
    )
  end

  def mark_ignored!(reason:, at: Time.current)
    update!(
      processing_status: "ignored",
      processed_at: at,
      processing_error: reason.to_s
    )
  end

  def mark_verified!(at: Time.current)
    update!(
      verification_status: "verified",
      verification_checked_at: at,
      verification_error: nil
    )
  end

  def mark_verification_failed!(
    error:,
    at: Time.current
  )
    update!(
      verification_status: "failed",
      verification_checked_at: at,
      verification_error: error.to_s
    )
  end

  def mark_verification_rejected!(
    reason:,
    at: Time.current
  )
    update!(
      verification_status: "rejected",
      verification_checked_at: at,
      verification_error: reason.to_s
    )
  end

  private

  def metadata_must_be_an_object
    return if metadata.is_a?(Hash)

    errors.add(
      :metadata,
      "must be a JSON object"
    )
  end
end
