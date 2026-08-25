class Training < ApplicationRecord
  AUTOMATIC_REMINDER_LEAD_TIME =
    1.day

  belongs_to :team

  has_many :training_availabilities,
           dependent: :destroy

  has_many :notifications,
           dependent: :nullify

  validates :title,
            presence: true

  validates :starts_at,
            presence: true

  validates :meet_time,
            presence: true

  validates :location,
            presence: true

  validate :meet_time_cannot_be_after_start_time

  after_save_commit :schedule_automatic_availability_reminder,
                    if:
                      :should_schedule_automatic_availability_reminder?

  private

  def meet_time_cannot_be_after_start_time
    return if
      meet_time.blank? ||
      starts_at.blank?

    if meet_time > starts_at
      errors.add(
        :meet_time,
        "must be before or at the training start time"
      )
    end
  end

  def schedule_automatic_availability_reminder
    return if starts_at.blank?

    expected_starts_at =
      starts_at.iso8601

    reminder_time =
      starts_at -
      AUTOMATIC_REMINDER_LEAD_TIME

    if reminder_time > Time.current
      AutomaticTrainingReminderJob
        .set(
          wait_until: reminder_time
        )
        .perform_later(
          id,
          expected_starts_at
        )

      return
    end

    fallback_time =
      Time.current +
      1.hour

    return if
      fallback_time >= starts_at

    AutomaticTrainingReminderJob
      .set(
        wait_until: fallback_time
      )
      .perform_later(
        id,
        expected_starts_at
      )
  end

  def should_schedule_automatic_availability_reminder?
    previously_new_record? ||
      saved_change_to_starts_at?
  end
end
