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

  private

  def metadata_must_be_an_object
    return if metadata.is_a?(Hash)

    errors.add(
      :metadata,
      "must be a JSON object"
    )
  end
end
