class User < ApplicationRecord
  before_validation :set_manager_verification_status, on: :create

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
  has_many :squad_selections, dependent: :destroy
  has_many :posts, dependent: :destroy
  has_many :notifications, dependent: :destroy
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

  def active_for_authentication?
    super && !deleted?
  end

  private

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
