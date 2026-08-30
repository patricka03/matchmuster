class ConversationParticipant < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  validates :user_id,
            uniqueness: {
              scope: :conversation_id
            }

  def unread_count
    scope =
      conversation
        .messages
        .where.not(
          sender_id: user_id
        )

    if cleared_at.present?
      scope =
        scope.where(
          "created_at > ?",
          cleared_at
        )
    end

    if last_read_at.present?
      scope =
        scope.where(
          "created_at > ?",
          last_read_at
        )
    end

    scope.count
  end

  def mark_read!
    touch(:last_read_at)
  end

  def clear_chat!
    now = Time.current

    update!(
      cleared_at: now,
      last_read_at: now
    )
  end
end
