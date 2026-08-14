class MatchPlayerStatsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :set_match
  before_action :authorise_approved_manager!

  def index
    squad =
      @match
        .squad_selections
        .includes(:user)
        .order(:id)

    stats_by_player_id =
      @match
        .match_player_stats
        .index_by(&:player_id)

    players =
      squad.map do |selection|
        player = selection.user
        stat = stats_by_player_id[player.id]

        {
          id: player.id,
          first_name: player.first_name,
          last_name: player.last_name,

          avatar_url:
            player.avatar.attached? ?
              url_for(player.avatar) :
              nil,

          selection_type: selection.selection_type,
          position: selection.position,

          goals: stat&.goals || 0,
          assists: stat&.assists || 0,
          clean_sheet: stat&.clean_sheet || false,
          yellow_cards: stat&.yellow_cards || 0,
          red_cards: stat&.red_cards || 0
        }
      end

    render json: {
      match: {
        id: @match.id,
        opponent: @match.opponent,
        kickoff_time: @match.kickoff_time,
        team_score: @match.team_score,
        opponent_score: @match.opponent_score
      },

      players: players
    }, status: :ok
  end

  def create
    submitted_stats = stats_params

    expected_player_ids =
      @match
        .squad_selections
        .pluck(:user_id)
        .sort

    submitted_player_ids =
      submitted_stats
        .map do |stat|
          stat[:player_id].to_i
        end
        .sort

    unless submitted_player_ids == expected_player_ids
      return render json: {
        error:
          "Stats must be submitted for every player in the saved matchday squad."
      }, status: :unprocessable_entity
    end

    if match_result_params[:team_score].blank? ||
       match_result_params[:opponent_score].blank?

      return render json: {
        error:
          "Please enter the final score before saving match stats."
      }, status: :unprocessable_entity
    end

    MatchPlayerStat.transaction do
      @match.update!(
        team_score:
          match_result_params[:team_score],

        opponent_score:
          match_result_params[:opponent_score]
      )

      submitted_stats.each do |stat_data|
        stat =
          @match
            .match_player_stats
            .find_or_initialize_by(
              player_id:
                stat_data[:player_id]
            )

        stat.assign_attributes(
          goals:
            stat_data[:goals],

          assists:
            stat_data[:assists],

          clean_sheet:
            stat_data[:clean_sheet],

          yellow_cards:
            stat_data[:yellow_cards],

          red_cards:
            stat_data[:red_cards]
        )

        stat.save!
      end
    end

    render json: {
      message:
        "Match result and player stats saved successfully.",

      match: {
        id: @match.id,
        team_score: @match.team_score,
        opponent_score: @match.opponent_score
      }
    }, status: :ok

  rescue ActiveRecord::RecordInvalid => error
    render json: {
      errors:
        error.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  private

  def set_team
    @team =
      Team.find(
        params[:team_id]
      )
  end

  def set_match
    @match =
      @team.matches.find(
        params[:match_id]
      )
  end

  def authorise_approved_manager!
    valid_manager =
      current_user.account_type == "manager" &&
      current_user.manager_verification_status == "approved"

    manager_membership =
      current_user.team_memberships.exists?(
        team_id: @team.id,
        role: "manager",
        status: "approved"
      )

    return if valid_manager &&
              manager_membership

    render json: {
      error:
        "Only an approved manager of this team can manage match stats."
    }, status: :forbidden
  end

  def match_result_params
    params
      .require(:match)
      .permit(
        :team_score,
        :opponent_score
      )
  end

  def stats_params
    params
      .require(:stats)
      .map do |stat|
        stat.permit(
          :player_id,
          :goals,
          :assists,
          :clean_sheet,
          :yellow_cards,
          :red_cards
        )
      end
  end
end
