class UserBlock < ApplicationRecord
  belongs_to :blocker,
             class_name: "User",
             inverse_of: :initiated_blocks

  belongs_to :blocked_user,
             class_name: "User",
             inverse_of: :received_blocks

  validates :blocked_user_id,
            uniqueness: {
              scope: :blocker_id,
              message: "has already been blocked"
            }

  validate :cannot_block_self

  private

  def cannot_block_self
    return if blocker_id.blank? ||
              blocked_user_id.blank?

    return unless blocker_id == blocked_user_id

    errors.add(
      :blocked_user,
      "cannot be yourself"
    )
  end
end
