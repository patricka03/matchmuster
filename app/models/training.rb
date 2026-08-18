class Training < ApplicationRecord
  belongs_to :team

  has_many :training_availabilities, dependent: :destroy

  validates :title, presence: true
  validates :starts_at, presence: true
  validates :meet_time, presence: true
  validates :location, presence: true

  validate :meet_time_cannot_be_after_start_time

  private

  def meet_time_cannot_be_after_start_time
    return if meet_time.blank? || starts_at.blank?

    if meet_time > starts_at
      errors.add(
        :meet_time,
        'must be before or at the training start time'
      )
    end
  end
end
