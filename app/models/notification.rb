class Notification < ApplicationRecord
  NOTIFICATION_TYPES = %w[
    announcement
    tactical_post
    post_created
    fixture_created
    fixture_updated
    fixture_cancelled
    availability_required
    availability_reminder
    squad_selected
    squad_updated
    match_payment_requested
    match_payment_paid
    match_payment_waived
    match_payment_amount_changed
  ].freeze

  belongs_to :user
  belongs_to :match, optional: true

  validates :title, :message, :notification_type, presence: true
  validates :notification_type, inclusion: { in: NOTIFICATION_TYPES }
end
