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
    player_availability_updated
    squad_selected
    squad_updated
    match_payment_requested
    match_payment_paid
    match_payment_waived
    match_payment_amount_changed
    manager_status_updated
    app_update
  ].freeze

  belongs_to :user
  belongs_to :match, optional: true
  belongs_to :post, optional: true
  belongs_to :match_payment, optional: true

  validates :title, :message, :notification_type, presence: true
  validates :notification_type, inclusion: { in: NOTIFICATION_TYPES }

  def self.broadcast_app_update!(title:, message:)
    manager_ids = User.where(
      account_type: "manager",
      manager_verification_status: "approved"
    ).pluck(:id)

    transaction do
      manager_ids.each do |manager_id|
        create!(
          user_id: manager_id,
          title: title,
          message: message,
          notification_type: "app_update"
        )
      end
    end

    manager_ids.count
  end
end
