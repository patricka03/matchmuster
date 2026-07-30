class Notification < ApplicationRecord
  NOTIFICATION_TYPES = %w[announcement match_created availability_reminder squad_selected].freeze

  belongs_to :user

  validates :title, :message, :notification_type, presence: true

  validates :notification_type, inclusion: { in: NOTIFICATION_TYPES }
end
