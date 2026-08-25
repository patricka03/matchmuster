class Training < ApplicationRecord
  AUTOMATIC_REMINDER_LEAD_TIME =
    1.day

  RECURRENCE_FREQUENCIES = %w[
    weekly
    fortnightly
  ].freeze

  RECURRENCE_GROUP_ID_FORMAT =
    /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i.freeze

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

  validates :recurrence_group_id,
            format: {
              with:
                RECURRENCE_GROUP_ID_FORMAT
            },
            allow_nil: true

  validates :recurrence_frequency,
            inclusion: {
              in:
                RECURRENCE_FREQUENCIES
            },
            allow_nil: true

  validates :recurrence_sequence,
            numericality: {
              only_integer: true,
              greater_than: 0
            },
            allow_nil: true

  validates :recurrence_sequence,
            uniqueness: {
              scope: %i[
                team_id
                recurrence_group_id
              ]
            },
            if: :recurring?

  validate :meet_time_cannot_be_after_start_time

  validate :recurrence_metadata_must_be_complete

  after_save_commit :schedule_automatic_availability_reminder,
                    if:
                      :should_schedule_automatic_availability_reminder?

  def recurring?
    recurrence_group_id.present?
  end

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

  def recurrence_metadata_must_be_complete
    metadata = [
      recurrence_group_id,
      recurrence_sequence,
      recurrence_frequency
    ]

    return if metadata.all?(&:blank?)
    return if metadata.all?(&:present?)

    errors.add(
      :base,
      "Recurring training metadata must be complete"
    )
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
