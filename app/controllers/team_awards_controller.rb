class TeamAwardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :authorise_team_member!

  def show
    season_start, season_end =
      current_season_range

    month_start =
      Time.current.beginning_of_month

    month_end =
      Time.current.end_of_month

    # ========================================
    # MOTM AWARDS
    # ========================================

    motm_awards =
      MatchAward
        .joins(:match, :user)
        .where(
          matches: {
            team_id: @team.id
          },
          award_type: "man_of_the_match"
        )

    monthly_awards =
      motm_awards.where(
        matches: {
          kickoff_time:
            month_start..month_end
        }
      )

    season_awards =
      motm_awards.where(
        matches: {
          kickoff_time:
            season_start...season_end
        }
      )

    # ========================================
    # PLAYER MATCH STATS
    # ========================================

    season_player_stats =
      MatchPlayerStat
        .joins(:match)
        .where(
          matches: {
            team_id: @team.id,
            kickoff_time:
              season_start...season_end
          }
        )

    # ========================================
    # COMPLETED MATCHES
    # ========================================

    completed_matches =
      @team
        .matches
        .where(
          kickoff_time:
            season_start...season_end
        )
        .where.not(
          team_score: nil,
          opponent_score: nil
        )

    render json: {
      month: {
        label:
          Time.current.strftime(
            "%B %Y"
          ),

        player_of_the_month:
          leaders_for(
            monthly_awards
          ),

        leaderboard:
          motm_leaderboard_for(
            monthly_awards
          )
      },

      season: {
        label:
          season_label(
            season_start,
            season_end
          ),

        player_of_the_season:
          leaders_for(
            season_awards
          ),

        leaderboard:
          motm_leaderboard_for(
            season_awards
          )
      },

      statistics: {
        label:
          season_label(
            season_start,
            season_end
          ),

        team:
          team_record(
            completed_matches
          ),

        top_scorers:
          stat_leaderboard(
            season_player_stats,
            :goals
          ),

        top_assists:
          stat_leaderboard(
            season_player_stats,
            :assists
          ),

        clean_sheets:
          clean_sheet_leaderboard(
            season_player_stats
          ),

        yellow_cards:
          stat_leaderboard(
            season_player_stats,
            :yellow_cards
          ),

        red_cards:
          stat_leaderboard(
            season_player_stats,
            :red_cards
          )
      },

      recent_man_of_the_match:
        recent_motm(
          motm_awards
        )
    }, status: :ok
  end

  private

  # ========================================
  # TEAM
  # ========================================

  def set_team
    @team =
      Team.find(
        params[:team_id]
      )
  end

  # ========================================
  # AUTHORISATION
  # ========================================

  def authorise_team_member!
    membership =
      current_user
        .team_memberships
        .find_by(
          team_id: @team.id,
          status: "approved"
        )

    authorised =
      case current_user.account_type
      when "player"
        membership&.role == "player"

      when "manager"
        membership&.role == "manager" &&
          current_user.manager_verification_status ==
            "approved"

      else
        false
      end

    return if authorised

    render json: {
      error:
        "You are not authorised to view team awards"
    }, status: :forbidden
  end

  # ========================================
  # MOTM LEADERBOARD
  # ========================================

  def motm_leaderboard_for(scope)
    counts =
      scope
        .group(:user_id)
        .count

    build_player_leaderboard(
      counts
    )
  end

  def leaders_for(scope)
    leaderboard =
      motm_leaderboard_for(
        scope
      )

    return [] if leaderboard.empty?

    highest_count =
      leaderboard
        .first[
          :motm_count
        ]

    leaderboard.select do |result|
      result[:motm_count] ==
        highest_count
    end
  end

  # ========================================
  # STAT LEADERBOARDS
  # ========================================

  def stat_leaderboard(
    scope,
    column
  )
    totals =
      scope
        .group(:player_id)
        .sum(column)
        .select do |_player_id, total|
          total.to_i > 0
        end

    build_stat_leaderboard(
      totals,
      column
    )
  end

  def clean_sheet_leaderboard(scope)
    totals =
      scope
        .where(
          clean_sheet: true
        )
        .group(:player_id)
        .count

    build_stat_leaderboard(
      totals,
      :clean_sheets
    )
  end

  def build_stat_leaderboard(
    totals,
    stat_name
  )
    return [] if totals.empty?

    users =
      User
        .where(
          id: totals.keys
        )
        .index_by(&:id)

    totals
      .filter_map do |player_id, total|
        player =
          users[player_id]

        next unless player

        {
          player:
            player_json(
              player
            ),

          stat:
            stat_name,

          total:
            total.to_i
        }
      end
      .sort_by do |result|
        [
          -result[:total],
          result[:player][:last_name].to_s,
          result[:player][:first_name].to_s
        ]
      end
      .first(10)
  end

  # ========================================
  # MOTM PLAYER BUILDER
  # ========================================

  def build_player_leaderboard(counts)
    return [] if counts.empty?

    users =
      User
        .where(
          id: counts.keys
        )
        .index_by(&:id)

    counts
      .filter_map do |user_id, motm_count|
        user =
          users[user_id]

        next unless user

        {
          player:
            player_json(
              user
            ),

          motm_count:
            motm_count
        }
      end
      .sort_by do |result|
        [
          -result[:motm_count],
          result[:player][:last_name].to_s,
          result[:player][:first_name].to_s
        ]
      end
  end

  # ========================================
  # TEAM RECORD
  # ========================================

  def team_record(scope)
    matches =
      scope.to_a

    wins =
      matches.count do |match|
        match.team_score >
          match.opponent_score
      end

    draws =
      matches.count do |match|
        match.team_score ==
          match.opponent_score
      end

    losses =
      matches.count do |match|
        match.team_score <
          match.opponent_score
      end

    goals_for =
      matches.sum do |match|
        match.team_score
      end

    goals_against =
      matches.sum do |match|
        match.opponent_score
      end

    {
      played:
        matches.count,

      wins:
        wins,

      draws:
        draws,

      losses:
        losses,

      goals_for:
        goals_for,

      goals_against:
        goals_against,

      goal_difference:
        goals_for -
        goals_against
    }
  end

  # ========================================
  # RECENT MOTM
  # ========================================

  def recent_motm(scope)
    scope
      .includes(
        :user,
        :match
      )
      .order(
        "matches.kickoff_time DESC"
      )
      .limit(10)
      .map do |award|
        {
          match: {
            id:
              award.match.id,

            opponent:
              award.match.opponent,

            kickoff_time:
              award.match.kickoff_time,

            team_score:
              award.match.team_score,

            opponent_score:
              award.match.opponent_score
          },

          player:
            player_json(
              award.user
            ),

          average_rating:
            award
              .average_rating
              .to_f
        }
      end
  end

  # ========================================
  # PLAYER JSON
  # ========================================

  def player_json(player)
    {
      id:
        player.id,

      first_name:
        player.first_name,

      last_name:
        player.last_name,

      avatar_url:
        player.avatar.attached? ?
          url_for(player.avatar) :
          nil
    }
  end

  # ========================================
  # SEASON
  # August → July
  # ========================================

  def current_season_range
    now =
      Time.current

    start_year =
      if now.month >= 8
        now.year
      else
        now.year - 1
      end

    season_start =
      Time.zone.local(
        start_year,
        8,
        1
      )

    season_end =
      Time.zone.local(
        start_year + 1,
        8,
        1
      )

    [
      season_start,
      season_end
    ]
  end

  def season_label(
    season_start,
    season_end
  )
    "#{season_start.year}/#{season_end.year.to_s.last(2)}"
  end
end
