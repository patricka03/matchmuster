module MatchRatingTestData
  def create_test_team
    Team.create!(
      name:
        "Test Team #{SecureRandom.hex(4)}"
    )
  end

  def create_test_user(
    first_name:,
    account_type: "player"
  )
    user =
      User.create!(
        first_name: first_name,
        last_name: "Tester",
        email:
          "#{first_name.downcase}-#{SecureRandom.hex(4)}@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        account_type: account_type
      )

    if account_type == "manager"
      user.update_columns(
        manager_verification_status: "approved",
        updated_at: Time.current
      )
    end

    user
  end

  def create_test_match(team:)
    Match.create!(
      team: team,
      opponent: "Test Opposition",
      location: "Test Ground",
      kickoff_time: 1.day.from_now,
      match_type: "friendly"
    )
  end

  def select_test_player(
    team:,
    match:,
    player:,
    position:
  )
    TeamMembership.create!(
      team: team,
      user: player,
      role: "player",
      preferred_position: position,
      status: "approved"
    )

    Availability.create!(
      match: match,
      user: player,
      status: "available"
    )

    SquadSelection.create!(
      match: match,
      user: player,
      selection_type: "starter",
      position: position
    )
  end

  def create_rating_context
    team = create_test_team
    match = create_test_match(team: team)

    rater =
      create_test_user(
        first_name: "Rater"
      )

    player =
      create_test_user(
        first_name: "Target"
      )

    select_test_player(
      team: team,
      match: match,
      player: rater,
      position: "CM"
    )

    select_test_player(
      team: team,
      match: match,
      player: player,
      position: "ST"
    )

    {
      team: team,
      match: match,
      rater: rater,
      player: player
    }
  end
    def submit_test_rating(
    match:,
    rater:,
    player:,
    rating:
  )
    MatchRating.create!(
      match: match,
      rater: rater,
      player: player,
      rating: rating
    )
  end

  def close_rating_window(match)
    match.update_columns(
      kickoff_time: 5.hours.ago,
      ratings_finalised_at: nil,
      updated_at: Time.current
    )

    match.reload
  end
end
