class Report < ApplicationRecord
  REASONS = %w[
    abuse
    bullying
    discrimination
    harassment
    inappropriate_content
    impersonation
    privacy_concern
    spam
    violence
    other
  ].freeze

  STATUSES = %w[
    pending
    reviewing
    actioned
    dismissed
  ].freeze

  REPORTABLE_TYPES = %w[
    Post
    MatchRating
    Message
  ].freeze

  has_many :moderation_actions, dependent: :destroy

  belongs_to :reporter, class_name: "User", inverse_of: :submitted_reports
  belongs_to :reported_user, class_name: "User", optional: true, inverse_of: :received_reports
  belongs_to :reportable, polymorphic: true, optional: true
  belongs_to :reviewed_by, class_name: "Developer", optional: true, inverse_of: :reviewed_reports

  validates :reason, presence: true, inclusion: { in: REASONS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :reportable_type, inclusion: { in: REPORTABLE_TYPES }, allow_nil: true
  validates :details, length: { maximum: 1_000 }
  validates :moderation_notes, length: { maximum: 2_000  }
  validates :details, presence: true, if: -> { reason == "other" }

  validate :report_target_present
  validate :cannot_report_self

  before_validation :normalise_reason
  before_validation :capture_content, on: :create
  after_create_commit :notify_moderators

  scope :newest_first,
        -> { order(created_at: :desc) }

  scope :unresolved,
        -> { where(status: %w[pending reviewing]) }

  private

  def normalise_reason
    # Accept values sent by older installed app builds as well.
    self.reason = { "hate_speech" => "discrimination", "sexual_content" => "inappropriate_content" }.fetch(reason, reason)
  end

  def capture_content
    snapshot = case reportable
               when Post
                 reportable.attributes.slice("id", "team_id", "title", "content", "post_type", "user_id")
               when MatchRating
                 reportable.attributes.slice("id", "match_id", "rater_id", "player_id", "rating", "comment")
               when Message
                 reportable.attributes.slice("id", "conversation_id", "sender_id", "body")
               else
                 {}
               end
    self.content_snapshot = (content_snapshot || {}).merge(snapshot).merge(
      "type" => reportable_type || "User",
      "reported_user_id" => reported_user_id,
      "captured_at" => Time.current.iso8601
    )
  end

  def notify_moderators
    ModerationAlertJob.perform_later(id)
  rescue StandardError => error
    # The durable developer review queue remains available if enqueueing fails.
    Rails.logger.error("Moderation alert enqueue failed for report #{id}: #{error.class}")
  end

  def report_target_present
    return if reported_user.present? ||
              reportable.present?

    errors.add(
      :base,
      "A user or piece of content must be reported"
    )
  end

  def cannot_report_self
    return if reported_user_id.blank?
    return unless reporter_id == reported_user_id

    errors.add(
      :reported_user,
      "cannot be yourself"
    )
  end
end
