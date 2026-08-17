class ModerationAction < ApplicationRecord
  ACTION_TYPES = %w[
    review_started
    report_dismissed
    content_removed
    user_suspended
    user_banned
    user_restored
    user_deleted
  ].freeze

  belongs_to :report

  belongs_to :developer,
             optional: true,
             inverse_of: :moderation_actions

  belongs_to :target_user,
             class_name: "User",
             optional: true,
             inverse_of:
               :moderation_actions_received

  validates :action_type,
            presence: true,
            inclusion: {
              in: ACTION_TYPES
            }

  validates :notes,
            length: {
              maximum: 2_000
            }
end
