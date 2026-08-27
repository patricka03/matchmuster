class User < ApplicationRecord
  before_validation :set_manager_verification_status, on: :create
  before_update :rotate_jti_when_access_status_changes

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  include Devise::JWT::RevocationStrategies::JTIMatcher

  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :rememberable,
         :validatable,
         :jwt_authenticatable,
         jwt_revocation_strategy: self

  self.skip_session_storage = [:http_auth, :params_auth, :jwt]

  has_many :team_memberships, dependent: :destroy
  has_many :teams, through: :team_memberships
  has_many :owned_teams,
           class_name: "Team",
           foreign_key: :owner_user_id,
           inverse_of: :owner_user
  has_many :squad_selections, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :push_devices, dependent: :destroy
  has_many :sent_notifications, class_name: "Notification", foreign_key: :actor_id, inverse_of: :actor, dependent: :nullify
  has_many :featured_notifications, class_name: "Notification", foreign_key: :featured_user_id, inverse_of: :featured_user, dependent: :nullify
  has_many :match_payments, dependent: :destroy
  has_many :availabilities, dependent: :destroy
  has_many :matches, through: :availabilities
  has_many :post_reads, dependent: :destroy
  has_many :read_posts, through: :post_reads, source: :post
  has_many :legal_acceptances, dependent: :destroy
  has_many :match_ratings_given, class_name: "MatchRating", foreign_key: :rater_id, dependent: :destroy
  has_many :match_ratings_received, class_name: "MatchRating", foreign_key: :player_id, dependent: :destroy
  has_many :match_awards, dependent: :destroy
  has_many :match_player_stats, foreign_key: :player_id, dependent: :destroy
  has_many :submitted_reports, class_name: "Report", foreign_key: :reporter_id, inverse_of: :reporter, dependent: :destroy
  has_many :received_reports, class_name: "Report", foreign_key: :reported_user_id, inverse_of: :reported_user, dependent: :nullify
  has_many :initiated_blocks, class_name: "UserBlock", foreign_key: :blocker_id, inverse_of: :blocker, dependent: :destroy
  has_many :blocked_users, through: :initiated_blocks, source: :blocked_user
  has_many :received_blocks, class_name: "UserBlock", foreign_key: :blocked_user_id, inverse_of: :blocked_user, dependent: :destroy
  has_many :blocked_by_users, through: :received_blocks, source: :blocker
  has_many :moderation_actions_received, class_name: "ModerationAction", foreign_key: :target_user_id, inverse_of: :target_user, dependent: :nullify
  has_many :training_availabilities, dependent: :destroy

  has_one_attached :avatar

  validates :first_name, :last_name, :account_type, presence: true
  validates :account_type, inclusion: { in: %w[player manager] }
  validates :manager_verification_status,
            presence: true,
            inclusion: { in: %w[pending approved rejected] },
            if: :manager?

  after_create_commit :create_initial_manager_status_notification, if: :manager?
  after_update_commit :create_manager_status_notification,
                      if: :saved_change_to_manager_verification_status?
  after_update_commit :send_manager_approval_email,
                      if: :saved_change_to_manager_verification_status?

  def manager?
    account_type == "manager"
  end

  def deleted?
    deleted_at.present?
  end

  def suspended?
    suspended_at.present?
  end

  def banned?
    banned_at.present?
  end

  def access_restricted?
    deleted? || suspended? || banned?
  end

  def active_for_authentication?
    super && !access_restricted?
  end

  private

  def rotate_jti_when_access_status_changes
    access_status_changed =
      will_save_change_to_deleted_at? ||
      will_save_change_to_suspended_at? ||
      will_save_change_to_banned_at?

    self.jti = SecureRandom.uuid if access_status_changed
  end

  def set_manager_verification_status
    self.manager_verification_status = "pending" if manager?
  end

  def create_initial_manager_status_notification
    notifications.create!(
      title: "Manager Application Received",
      message: "Your manager application is pending review. We will notify you when its status changes.",
      notification_type: "manager_status_updated"
    )
  end

  def create_manager_status_notification
    title, message = manager_status_notification_content

    notifications.create!(
      title: title,
      message: message,
      notification_type: "manager_status_updated"
    )
  end

  def manager_status_notification_content
    case manager_verification_status
    when "approved"
      [
        "Manager Account Approved",
        "Your manager account has been approved. You can now access MatchMuster's manager features."
      ]
    when "rejected"
      [
        "Manager Application Update",
        "Your manager application was not approved. Please contact MatchMuster support if you need help."
      ]
    else
      [
        "Manager Application Pending",
        "Your manager application is pending review. We will notify you when its status changes."
      ]
    end
  end

  def send_manager_approval_email
    return unless manager_verification_status == "approved"

    UserMailer.manager_approved_email(self).deliver_later
  end
end
