class SquadAnalytics
  MINIMUM_SAMPLE = 3

  def initialize(team:, at: Time.current)
    @team = team
    @at = at
  end

  def call
    players = approved_players
    completed = completed_matches
    completed_ids = completed.map(&:id)
    selections = SquadSelection
      .includes(:user, :match)
      .where(match_id: completed_ids, user_id: players.map(&:id))
      .to_a
    availabilities = Availability
      .joins(:match)
      .where(matches: { team_id: team.id }, user_id: players.map(&:id))
      .to_a
    dropouts = AvailabilityStatusChange
      .where(team_id: team.id, user_id: players.map(&:id), was_selected: true)
      .where(from_status: "available", to_status: "unavailable")
      .group(:user_id)
      .count

    team_wins = completed.count { |match| won?(match) }
    team_rate = percentage(team_wins, completed.length)
    player_rows = players.map do |player|
      player_selections = selections.select { |selection| selection.user_id == player.id }
      selected_matches = player_selections.map(&:match)
      wins = selected_matches.count { |match| won?(match) }
      draws = selected_matches.count { |match| drawn?(match) }
      losses = selected_matches.count { |match| lost?(match) }
      player_availability = availabilities.select { |availability| availability.user_id == player.id }
      available = player_availability.count { |availability| availability.status == "available" }
      unavailable = player_availability.count { |availability| availability.status == "unavailable" }
      appearances = selected_matches.length
      win_rate = percentage(wins, appearances)

      {
        player: player_json(player),
        appearances: appearances,
        starts: player_selections.count { |selection| selection.selection_type == "starter" },
        substitute_selections: player_selections.count { |selection| selection.selection_type == "substitute" },
        wins: wins,
        draws: draws,
        losses: losses,
        win_rate: win_rate,
        team_win_rate: team_rate,
        win_rate_difference: appearances >= MINIMUM_SAMPLE ? (win_rate - team_rate).round(1) : nil,
        sample_qualified: appearances >= MINIMUM_SAMPLE,
        availability_responses: player_availability.length,
        available_count: available,
        unavailable_count: unavailable,
        availability_rate: percentage(available, player_availability.length),
        selected_dropouts: dropouts.fetch(player.id, 0)
      }
    end

    {
      generated_at: at,
      minimum_sample: MINIMUM_SAMPLE,
      overview: {
        players: players.length,
        completed_matches: completed.length,
        team_wins: team_wins,
        team_draws: completed.count { |match| drawn?(match) },
        team_losses: completed.count { |match| lost?(match) },
        team_win_rate: team_rate,
        injured_or_unavailable: active_fitness_statuses.count,
        recorded_dropouts: dropouts.values.sum
      },
      fitness: active_fitness_statuses.map { |status| fitness_json(status) },
      player_metrics: player_rows.sort_by { |row| [-row[:appearances], row[:player][:name]] },
      impact_leaders: player_rows
        .select { |row| row[:sample_qualified] }
        .sort_by { |row| [-row[:win_rate_difference], -row[:appearances], row[:player][:name]] },
      reliability_leaders: player_rows
        .select { |row| row[:availability_responses].positive? }
        .sort_by { |row| [-row[:availability_rate], -row[:available_count], row[:player][:name]] },
      dropout_leaders: player_rows
        .select { |row| row[:selected_dropouts].positive? }
        .sort_by { |row| [-row[:selected_dropouts], row[:player][:name]] },
      partnerships: partnership_rows(selections, completed)
    }
  end

  private

  attr_reader :team, :at

  def approved_players
    User
      .joins(:team_memberships)
      .where(team_memberships: { team_id: team.id, role: "player", status: "approved" })
      .order(:first_name, :last_name, :id)
      .distinct
      .to_a
  end

  def completed_matches
    team.matches
      .where(cancelled_at: nil)
      .where("kickoff_time <= ?", at)
      .where.not(team_score: nil, opponent_score: nil)
      .order(:kickoff_time)
      .to_a
  end

  def active_fitness_statuses
    @active_fitness_statuses ||= PlayerFitnessStatus
      .includes(:user)
      .where(team_id: team.id)
      .where.not(status: "fit")
      .order(expected_return_on: :asc, updated_at: :desc)
      .to_a
  end

  def partnership_rows(selections, completed)
    match_by_id = completed.index_by(&:id)
    pairs = Hash.new { |hash, key| hash[key] = { played: 0, wins: 0 } }

    selections.group_by(&:match_id).each do |match_id, match_selections|
      match = match_by_id[match_id]
      next unless match

      match_selections.map(&:user).uniq.combination(2).each do |first, second|
        key = [first.id, second.id].sort
        pairs[key][:players] = [first, second].sort_by(&:id)
        pairs[key][:played] += 1
        pairs[key][:wins] += 1 if won?(match)
      end
    end

    pairs.values
      .select { |row| row[:played] >= MINIMUM_SAMPLE }
      .map do |row|
        {
          players: row[:players].map { |player| player_json(player) },
          played: row[:played],
          wins: row[:wins],
          win_rate: percentage(row[:wins], row[:played])
        }
      end
      .sort_by { |row| [-row[:win_rate], -row[:played]] }
      .first(10)
  end

  def fitness_json(status)
    {
      id: status.id,
      player: player_json(status.user),
      status: status.status,
      note: status.note,
      expected_return_on: status.expected_return_on,
      updated_at: status.updated_at
    }
  end

  def player_json(player)
    {
      id: player.id,
      name: [player.first_name, player.last_name].compact.join(" ").strip.presence || "Player",
      first_name: player.first_name,
      last_name: player.last_name,
      preferred_position: player.team_memberships.find { |membership| membership.team_id == team.id }&.preferred_position
    }
  end

  def percentage(numerator, denominator)
    return 0.0 if denominator.zero?

    ((numerator.to_f / denominator) * 100).round(1)
  end

  def won?(match)
    match.team_score > match.opponent_score
  end

  def drawn?(match)
    match.team_score == match.opponent_score
  end

  def lost?(match)
    match.team_score < match.opponent_score
  end
end
