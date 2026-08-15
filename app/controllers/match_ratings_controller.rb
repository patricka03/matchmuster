class MatchRatingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_match

  def create
    unless eligible_rater?
      return render json: {
        error: "You are not eligible to rate players for this match."
      }, status: :forbidden
    end

    unless @match.ratings_open?
      if Time.current < @match.ratings_open_at
        return render json: {
          error: "Ratings are not open yet.",
          ratings_open_at: @match.ratings_open_at
        }, status: :unprocessable_entity
      end

      return render json: {
        error: "The rating window has closed."
      }, status: :unprocessable_entity
    end

    if @match.ratings_submitted_by?(current_user.id)
      return render json: {
        error: "You have already submitted your ratings for this match."
      }, status: :unprocessable_entity
    end

    submitted_ratings = ratings_params

    expected_player_ids =
      @match
        .rating_target_ids_for(current_user.id)
        .sort

    submitted_player_ids =
      submitted_ratings
        .map { |rating| rating[:player_id].to_i }
        .sort

    unless submitted_player_ids == expected_player_ids
      return render json: {
        error: "You must rate every eligible player before submitting."
      }, status: :unprocessable_entity
    end

    created_ratings = []

    MatchRating.transaction do
      submitted_ratings.each do |rating_data|
        rating =
          @match.match_ratings.create!(
            rater: current_user,
            player_id: rating_data[:player_id],
            rating: rating_data[:rating],
            comment: rating_data[:comment]
          )

        created_ratings << rating
      end

      notify_managers_of_rating_submission
    end

    render json: {
      message: "Ratings submitted successfully.",
      ratings_submitted: created_ratings.count,
      ratings_complete: @match.ratings_complete?,
      submitted_voters: @match.submitted_rating_voters,
      total_voters: @match.total_rating_voters
    }, status: :created

  rescue ActiveRecord::RecordInvalid => error
    render json: {
      errors: error.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  def status
    eligible = eligible_rater?

    render json: {
      eligible: eligible,

      submitted:
        eligible &&
        @match.ratings_submitted_by?(current_user.id),

      can_submit:
        eligible &&
        @match.ratings_open? &&
        !@match.ratings_submitted_by?(current_user.id),

      ratings_open: @match.ratings_open?,

      ratings_closed: @match.ratings_closed?,

      ratings_finalised:
        @match.ratings_finalised_at.present?,

      ratings_open_at:
        @match.ratings_open_at,

      ratings_close_at:
        @match.ratings_close_at,

      ratings_complete:
        @match.ratings_complete?,

      submitted_voters:
        @match.submitted_rating_voters,

      total_voters:
        @match.total_rating_voters,

      turnout_percentage:
        @match.rating_turnout_percentage,

      players:
        eligible ?
          rating_players_json :
          []
    }, status: :ok
  end

  def results
    unless eligible_rater?
      return render json: {
        error: "You are not eligible to view ratings for this match."
      }, status: :forbidden
    end

    unless @match.ratings_finalised_at.present?
      return render json: {
        ratings_complete: @match.ratings_complete?,
        results_locked: true,
        submitted_voters: @match.submitted_rating_voters,
        total_voters: @match.total_rating_voters,
        turnout_percentage: @match.rating_turnout_percentage,
        ratings_close_at: @match.ratings_close_at,
        message: "Results will be revealed when the rating window closes."
      }, status: :ok
    end

    render json: {
      ratings_complete: @match.ratings_complete?,
      results_locked: false,

      submitted_voters:
        @match.submitted_rating_voters,

      total_voters:
        @match.total_rating_voters,

      turnout_percentage:
        @match.rating_turnout_percentage,

      results:
        @match.rating_results.map do |result|
          result_json(result)
        end,

      man_of_the_match:
        @match.man_of_the_match.map do |result|
          result_json(result)
        end
    }, status: :ok
  end

  private

  def set_match
    team =
      Team.find(params[:team_id])

    @match =
      team.matches.find(
        params[:match_id]
      )
  end

  def eligible_rater?
    @match
      .rating_rater_ids
      .include?(current_user.id)
  end

  def notify_managers_of_rating_submission
    return unless
      current_user.account_type ==
      "player"

    NotificationEvents.motm_ratings_submitted(
      match: @match,
      voter: current_user
    )
  end

  def rating_players_json
    player_ids =
      @match.rating_target_ids_for(
        current_user.id
      )

    User.where(id: player_ids).map do |player|
      {
        id: player.id,
        first_name: player.first_name,
        last_name: player.last_name,

        avatar_url:
          player.avatar.attached? ?
            url_for(player.avatar) :
            nil
      }
    end
  end

  def result_json(result)
    {
      player: {
        id: result[:player].id,

        first_name:
          result[:player].first_name,

        last_name:
          result[:player].last_name,

        avatar_url:
          result[:player].avatar.attached? ?
            url_for(result[:player].avatar) :
            nil
      },

      average_rating:
        result[:average_rating].to_f,

      ratings_received:
        result[:ratings_received]
    }
  end

  def ratings_params
    params
      .require(:ratings)
      .map do |rating|
        rating.permit(
          :player_id,
          :rating,
          :comment
        )
      end
  end
end
