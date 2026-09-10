class Message < ApplicationRecord
  has_many :reports, as: :reportable, dependent: :nullify

  belongs_to :conversation,
             touch: true
  belongs_to :sender,
             class_name: "User"

  before_validation :normalise_body
  before_destroy :remove_notification_previews

  validates :body, objectionable_content: true

  validates :body,
            presence: true,
            length: {
              maximum: 2_000
            }

  private

  def remove_notification_previews
    # Notifications do not have a message_id. Clear this sender's previews for
    # this conversation so removed or previously edited content cannot linger.
    conversation.notifications.where(notification_type: "direct_message", actor_id: sender_id).destroy_all
  end

  def normalise_body
    self.body = body.to_s.strip
  end
end
