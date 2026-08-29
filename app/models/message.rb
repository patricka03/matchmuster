class Message < ApplicationRecord
  belongs_to :conversation,
             touch: true
  belongs_to :sender,
             class_name: "User"

  before_validation :normalise_body

  validates :body,
            presence: true,
            length: {
              maximum: 2_000
            }

  private

  def normalise_body
    self.body = body.to_s.strip
  end
end
