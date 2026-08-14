class Match < ApplicationRecord
  MATCH_TYPES = %w[league cup friendly].freeze

  FORMATIONS = [
    "4-4-2",
    "4-4-2 Diamond",
    "4-3-3",
    "4-2-3-1",
    "4-1-4-1",
    "4-5-1",
    "4-2-4",
    "3-5-2",
    "3-4-3",
    "3-4-2-1",
    "3-1-4-2",
    "5-3-2",
    "5-4-1",
    "5-2-3"
  ].freeze

  before_validation :normalise_match_type

  after_save_commit :schedule_match_background_jobs,
                  if: :should_schedule_match_background_jobs?

  belongs_to :team

  has_many :availabilities,
           dependent: :destroy

  has_many :users,
           through: :availabilities

  has_many :squad_selections,
           dependent: :destroy

  has_many :match_payments,
           dependent: :destroy

  has_many :notifications,
           dependent: :nullify

  has_many :match_ratings,
           dependent: :destroy

  has_many :match_awards,
           dependent: :destroy

  has_many :match_player_stats,
           dependent: :destroy

  validates :opponent,
            :match_type,
            :location,
            :kickoff_time,
            presence: true

  validates :match_type,
            inclusion: {
              in: MATCH_TYPES
            }

  validates :formation,
            inclusion: {
              in: FORMATIONS
            },
            allow_nil: true

  validate :kickoff_time_cannot_be_in_the_past,
           on: :create

  validates :description,
            length: {
              maximum: 500
            },
            allow_blank: true

  validates :team_score,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            },
            allow_nil: true

  validates :opponent_score,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            },
            allow_nil: true

  # ========================================
  # MATCH RATINGS
  # ========================================

  def selected_player_ids
    squad_selections.pluck(
      :user_id
    )
  end

  def selected_players
    User.where(
      id: selected_player_ids
    )
  end

  def approved_manager_ids
    User
      .joins(
        :team_memberships
      )
      .where(
        account_type: "manager",
        manager_verification_status:
          "approved",

        team_memberships: {
          team_id: team.id,
          role: "manager",
          status: "approved"
        }
      )
      .distinct
      .pluck(
        :id
      )
  end

  def rating_rater_ids
    (
      selected_player_ids +
      approved_manager_ids
    ).uniq
  end

  def rating_target_ids_for(
    rater_id
  )
    player_ids =
      selected_player_ids

    if player_ids.include?(
      rater_id
    )
      player_ids -
        [
          rater_id
        ]
    elsif approved_manager_ids.include?(
      rater_id
    )
      player_ids
    else
      []
    end
  end

  def expected_rating_count_for(
    rater_id
  )
    rating_target_ids_for(
      rater_id
    ).count
  end

  def ratings_submitted_by?(
    rater_id
  )
    expected_ids =
      rating_target_ids_for(
        rater_id
      )

    return false if expected_ids.empty?

    submitted_ids =
      match_ratings
        .where(
          rater_id: rater_id
        )
        .pluck(
          :player_id
        )

    submitted_ids.sort ==
      expected_ids.sort
  end

  def submitted_rating_rater_ids
    rating_rater_ids.select do |rater_id|
      ratings_submitted_by?(
        rater_id
      )
    end
  end

  def ratings_complete?
    return false if rating_rater_ids.empty?

    rating_rater_ids.all? do |rater_id|
      ratings_submitted_by?(
        rater_id
      )
    end
  end

  # ========================================
  # RATING WINDOW
  # ========================================

  def ratings_open_at
    kickoff_time +
      2.hours
  end

  def ratings_close_at
    kickoff_time +
      4.hours
  end

  def ratings_open?
    Time.current >= ratings_open_at &&
      Time.current < ratings_close_at &&
      ratings_finalised_at.nil?
  end

  def ratings_closed?
    Time.current >=
      ratings_close_at
  end

  # ========================================
  # VOTER TURNOUT
  # ========================================

  def total_rating_voters
    rating_rater_ids.count
  end

  def submitted_rating_voters
    submitted_rating_rater_ids.count
  end

  def rating_turnout_percentage
    return 0.0 if total_rating_voters.zero?

    (
      submitted_rating_voters.to_f /
      total_rating_voters *
      100
    ).round(
      1
    )
  end

  def enough_rating_turnout?
    return false if total_rating_voters.zero?

    submitted_rating_voters.to_f /
      total_rating_voters >= 0.5
  end

  # ========================================
  # RESULTS
  # ========================================

  def calculated_rating_results
    selected_players.filter_map do |player|
      ratings =
        match_ratings.where(
          player_id:
            player.id
        )

      next if ratings.empty?

      {
        player:
          player,

        average_rating:
          ratings
            .average(
              :rating
            )
            .round(
              1
            ),

        ratings_received:
          ratings.count
      }
    end.sort_by do |result|
      -result[
        :average_rating
      ].to_f
    end
  end

  def rating_results
    return [] unless
      ratings_finalised_at.present?

    calculated_rating_results
  end

  def man_of_the_match
    return [] unless
      ratings_finalised_at.present?

    winner_ids =
      match_awards
        .where(
          award_type:
            "man_of_the_match"
        )
        .pluck(
          :user_id
        )

    calculated_rating_results.select do |result|
      winner_ids.include?(
        result[
          :player
        ].id
      )
    end
  end

  # ========================================
  # FINALISE MATCH RATINGS
  # ========================================

  def finalise_ratings!
    return if
      ratings_finalised_at.present?

    unless ratings_closed?
      raise StandardError,
            "Ratings cannot be finalised before the voting window closes."
    end

    transaction do
      if enough_rating_turnout?
        results =
          calculated_rating_results

        if results.any?
          highest_average =
            results
              .map do |result|
                result[
                  :average_rating
                ]
              end
              .max

          winners =
            results.select do |result|
              result[
                :average_rating
              ] ==
                highest_average
            end

          winners.each do |winner|
            match_awards.create!(
              user:
                winner[
                  :player
                ],

              award_type:
                "man_of_the_match",

              average_rating:
                winner[
                  :average_rating
                ],

              awarded_at:
                Time.current
            )
          end
        end
      end

      update!(
        ratings_finalised_at:
          Time.current
      )
    end
  end

  private

  # ========================================
  # SCHEDULE AVAILABILITY DEADLINE
  # ========================================

  def schedule_availability_deadline_job
    return if kickoff_time.blank?

    expected_kickoff_time =
      kickoff_time.iso8601

    deadline =
      kickoff_time -
      2.days

    if deadline <= Time.current
      AvailabilityDeadlineJob.perform_later(
        id,
        expected_kickoff_time
      )
    else
      AvailabilityDeadlineJob
        .set(
          wait_until: deadline
        )
        .perform_later(
          id,
          expected_kickoff_time
        )
    end
  end

  # ========================================
  # SCHEDULE MATCH RATING JOBS
  # ========================================

  def schedule_match_rating_jobs
    return if kickoff_time.blank?

    expected_kickoff_time =
      kickoff_time.iso8601

    MatchRatingOpenJob
      .set(
        wait_until: ratings_open_at
      )
      .perform_later(
        id,
        expected_kickoff_time
      )

    MatchRatingReminderJob
      .set(
        wait_until:
          ratings_open_at + 30.minutes
      )
      .perform_later(
        id,
        expected_kickoff_time,
        1
      )

    MatchRatingReminderJob
      .set(
        wait_until:
          ratings_open_at + 1.hour
      )
      .perform_later(
        id,
        expected_kickoff_time,
        2
      )

    MatchRatingReminderJob
      .set(
        wait_until:
          ratings_open_at + 90.minutes
      )
      .perform_later(
        id,
        expected_kickoff_time,
        3
      )

    MatchRatingFinaliseJob
      .set(
        wait_until: ratings_close_at
      )
      .perform_later(
        id,
        expected_kickoff_time
      )
  end

# ========================================
# SCHEDULE MATCH BACKGROUND JOBS
# ========================================

  def schedule_match_background_jobs
    schedule_availability_deadline_job
    schedule_match_rating_jobs
  end

  def should_schedule_match_background_jobs?
    previously_new_record? ||
      saved_change_to_kickoff_time?
  end

  # ========================================
  # NORMALISE MATCH TYPE
  # ========================================

  def normalise_match_type
    self.match_type =
      match_type
        .to_s
        .downcase
        .strip
  end

  # ========================================
  # KICK-OFF VALIDATION
  # ========================================

  def kickoff_time_cannot_be_in_the_past
    return if
      kickoff_time.blank?

    if kickoff_time <
        Time.current

      errors.add(
        :kickoff_time,
        "cannot be in the past"
      )
    end
  end
end
