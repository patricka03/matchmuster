class UserBlock < ApplicationRecord
  attr_accessor :reported_content

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

  after_create :create_safety_report!

  private

  def create_safety_report!
    blocker.submitted_reports.create!(
      reported_user: blocked_user,
      reportable: reported_content,
      reason: "other",
      details: "The reporter blocked this member. Review the block and any attached content.",
      content_snapshot: { "trigger" => "user_block" }
    )
  end

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
