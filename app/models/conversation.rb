class Conversation < ApplicationRecord
  CONVERSATION_TYPES = %w[direct].freeze

  belongs_to :team
  belongs_to :created_by,
             class_name: "User",
             optional: true

  has_many :conversation_participants,
           dependent: :destroy
  has_many :participants,
           through: :conversation_participants,
           source: :user
  has_many :messages,
           dependent: :destroy
  has_many :notifications,
           dependent: :nullify

  validates :conversation_type,
            presence: true,
            inclusion: {
              in: CONVERSATION_TYPES
            }

  validates :direct_key,
            presence: true,
            uniqueness: {
              scope: :team_id
            }

  class << self
    def direct_between!(team:, first_user:, second_user:)
      key = [first_user.id, second_user.id].sort.join(":")

      conversation =
        find_or_initialize_by(
          team: team,
          direct_key: key
        )

      if conversation.persisted?
        return ensure_direct_participants!(
          conversation,
          first_user,
          second_user
        )
      end

      conversation.created_by = first_user
      conversation.conversation_type = "direct"

      transaction do
        conversation.save!
        ensure_direct_participants!(
          conversation,
          first_user,
          second_user
        )
      end

      conversation
    rescue ActiveRecord::RecordNotUnique
      conversation =
        find_by!(
          team: team,
          direct_key: key
        )

      ensure_direct_participants!(
        conversation,
        first_user,
        second_user
      )
    end

    def blocked_between?(first_user:, second_user:)
      UserBlock
        .where(
          blocker_id: first_user.id,
          blocked_user_id: second_user.id
        )
        .or(
          UserBlock.where(
            blocker_id: second_user.id,
            blocked_user_id: first_user.id
          )
        )
        .exists?
    end

    private

    def ensure_direct_participants!(conversation, first_user, second_user)
      [first_user, second_user].each do |user|
        conversation
          .conversation_participants
          .create_or_find_by!(
            user: user
          )
      end

      conversation
    end
  end

  def participant_record_for(user)
    conversation_participants.find_by(
      user_id: user.id
    )
  end

  def participant?(user)
    conversation_participants.exists?(
      user_id: user.id
    )
  end

  def other_participant_for(user)
    participants.where.not(id: user.id).first
  end
end
