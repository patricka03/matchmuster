class RecurringTrainingService
  class InvalidSchedule < ArgumentError; end

  MIN_OCCURRENCES = 2
  MAX_OCCURRENCES = 52

  INTERVAL_WEEKS = {
    "weekly" => 1,
    "fortnightly" => 2
  }.freeze

  class << self
    def call(
      team:,
      attributes:,
      frequency:,
      occurrences:
    )
      new(
        team: team,
        attributes: attributes,
        frequency: frequency,
        occurrences: occurrences
      ).call
    end
  end

  def initialize(
    team:,
    attributes:,
    frequency:,
    occurrences:
  )
    @team =
      team

    @attributes =
      attributes
        .to_h
        .symbolize_keys

    @frequency =
      frequency
        .to_s
        .strip
        .downcase

    @occurrences =
      parse_occurrences(
        occurrences
      )
  end

  def call
    validate_schedule!

    recurrence_group_id =
      SecureRandom.uuid

    trainings = []

    Training.transaction do
      @occurrences.times do |index|
        offset =
          (
            index *
            interval_weeks
          ).weeks

        trainings <<
          @team
            .trainings
            .create!(
              @attributes.merge(
                starts_at:
                  @starts_at +
                  offset,
                meet_time:
                  @meet_time +
                  offset,
                recurrence_group_id:
                  recurrence_group_id,
                recurrence_sequence:
                  index + 1,
                recurrence_frequency:
                  @frequency
              )
            )
      end
    end

    trainings

  rescue ActiveRecord::RecordInvalid => error
    raise InvalidSchedule,
          error
            .record
            .errors
            .full_messages
            .to_sentence
  end

  private

  def validate_schedule!
    unless @team.is_a?(Team) &&
           @team.persisted?
      raise InvalidSchedule,
            "Team must be persisted"
    end

    unless INTERVAL_WEEKS.key?(
      @frequency
    )
      raise InvalidSchedule,
            "Frequency must be weekly or fortnightly"
    end

    unless @occurrences&.between?(
      MIN_OCCURRENCES,
      MAX_OCCURRENCES
    )
      raise InvalidSchedule,
            "Occurrences must be between #{MIN_OCCURRENCES} and #{MAX_OCCURRENCES}"
    end

    @starts_at =
      parse_time(
        @attributes[
          :starts_at
        ]
      )

    @meet_time =
      parse_time(
        @attributes[
          :meet_time
        ]
      )

    unless @starts_at
      raise InvalidSchedule,
            "Starts at is invalid"
    end

    unless @meet_time
      raise InvalidSchedule,
            "Meet time is invalid"
    end

    return if @meet_time <= @starts_at

    raise InvalidSchedule,
          "Meet time must be before or at the training start time"
  end

  def interval_weeks
    INTERVAL_WEEKS.fetch(
      @frequency
    )
  end

  def parse_occurrences(value)
    Integer(
      value.to_s,
      10
    )

  rescue ArgumentError,
         TypeError
    nil
  end

  def parse_time(value)
    return value if
      value.is_a?(
        ActiveSupport::TimeWithZone
      )

    return value.in_time_zone if
      value.is_a?(Time) ||
      value.is_a?(DateTime)

    Time.zone.parse(
      value.to_s
    )

  rescue ArgumentError,
         TypeError
    nil
  end
end
