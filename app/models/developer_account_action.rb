class DeveloperAccountAction < ApplicationRecord
  ACTION_TYPES = %w[
    user_suspended
    user_banned
    user_restored
    user_deleted
  ].freeze

  belongs_to :developer

  belongs_to :target_user,
             class_name: "User"

  validates :action_type,
            presence: true,
            inclusion: {
              in: ACTION_TYPES
            }

  validates :notes,
            presence: true,
            length: {
              maximum: 2_000
            }
end
