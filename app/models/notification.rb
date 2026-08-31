class Notification < ApplicationRecord
  AVAILABILITY_ACTION_TYPES = %w[
    fixture_created
    availability_required
    availability_reminder
  ].freeze

  TRAINING_AVAILABILITY_ACTION_TYPES = %w[
    training_availability_reminder
  ].freeze

  ACTIONABLE_TYPES = (
    AVAILABILITY_ACTION_TYPES +
    TRAINING_AVAILABILITY_ACTION_TYPES + %w[
      squad_selection_reminder
      match_payment_requested
      match_payment_amount_changed
      match_payment_reminder
      join_request_received
      team_join_requested
      motm_voting_open
      match_rating_open
      match_rating_reminder
      subscription_preview_reminder
    ]
  ).uniq.freeze

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

squad_selection_reminder
match_kickoff_reminder
match_started

training_start_reminder
training_started


    match_payment_requested
    match_payment_paid
    match_payment_waived
    match_payment_amount_changed
    match_payment_reminder

    join_request_received
    membership_approved
    membership_rejected
    team_membership_removed
    player_joined
    team_updated

    team_join_requested
    team_join_approved
    team_join_rejected

    motm_voting_open
    motm_vote_received
    motm_announced

    match_rating_open
    match_rating_reminder
    man_of_the_match
    match_rating_result

    manager_status_updated
    account_welcome
    app_update

    subscription_preview_reminder

    training_availability_updated
    training_availability_reminder

    match_late_update
    direct_message
  ].freeze

  belongs_to :user

  belongs_to :actor,
             class_name: "User",
             optional: true,
             inverse_of: :sent_notifications

  belongs_to :featured_user,
             class_name: "User",
             optional: true,
             inverse_of: :featured_notifications

  belongs_to :team,
             optional: true

  belongs_to :match,
             optional: true

  belongs_to :training,
             optional: true

  belongs_to :conversation,
             optional: true

  belongs_to :post,
             optional: true

  belongs_to :match_payment,
             optional: true

  validates :title,
            :message,
            :notification_type,
            presence: true

  validates :notification_type,
            inclusion: {
              in: NOTIFICATION_TYPES
            }

  scope :newest_first,
        -> { order(created_at: :desc) }

  scope :unread,
        -> { where(read: false, opened_at: nil) }

  scope :kept,
        -> { where.not(kept_at: nil) }

  after_create_commit :deliver_native_push

  def self.create_once!(
    user:,
    deduplication_key:,
    **attributes
  )
    create_or_find_by!(
      user_id: user.id,
      deduplication_key: deduplication_key
    ) do |notification|
      notification.assign_attributes(attributes)
    end
  end

  def self.broadcast_app_update!(
    title:,
    message:
  )
    manager_ids =
      User
        .where(
          account_type: "manager",
          manager_verification_status:
            "approved"
        )
        .pluck(:id)

    transaction do
      manager_ids.each do |manager_id|
        create!(
          user_id: manager_id,
          title: title,
          message: message,
          notification_type:
            "app_update"
        )
      end
    end

    manager_ids.count
  end

  private

  def deliver_native_push
    FirebasePushService.to_user(
      user: user,
      title: title,
      body: message,
      data: native_push_data
    )
  rescue StandardError => error
    Rails.logger.error(
      "Native push delivery failed for " \
      "Notification #{id}: " \
      "#{error.class}: #{error.message}"
    )

    0
  end

  def native_push_data
    {
      notification_id: id,
      notification_type: notification_type,
      team_id: team_id,
      match_id: match_id,
      post_id: post_id,
      match_payment_id: match_payment_id,
      featured_user_id: featured_user_id,
      training_id: training_id,
      conversation_id: conversation_id
    }
  end
end
