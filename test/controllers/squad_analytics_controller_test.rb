require "test_helper"

class SquadAnalyticsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @sequence = 0
    @now = Time.zone.parse("2026-09-10 12:00:00")
    @manager = create_user("manager")
    @player = create_user("player")
    @team = Team.create!(name: "Squad Insight FC")
    TeamMembership.create!(user: @manager, team: @team, role: "manager", status: "approved", preferred_position: "CM")
    TeamMembership.create!(user: @player, team: @team, role: "player", status: "approved", preferred_position: "ST")
  end

  test "Free manager receives the Squad Analytics Plus gate" do
    get endpoint, headers: auth_headers(@manager), as: :json

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "plus_required", body.fetch("code")
    assert_equal "squad_analytics", body.fetch("feature")
  end

  test "Plus manager receives match impact and availability metrics" do
    travel_to(@now) do
      enable_plus!
      match = completed_match(team_score: 3, opponent_score: 1)
      Availability.create!(match: match, user: @player, status: "available")
      SquadSelection.create!(match: match, user: @player, selection_type: "starter", position: "ST")

      get endpoint, headers: auth_headers(@manager), as: :json

      assert_response :ok
      body = JSON.parse(response.body)
      assert_equal 1, body.dig("overview", "completed_matches")
      assert_equal 100.0, body.dig("overview", "team_win_rate")
      player = body.fetch("player_metrics").first
      assert_equal @player.id, player.dig("player", "id")
      assert_equal 1, player.fetch("appearances")
      assert_equal 1, player.fetch("wins")
      assert_equal 100.0, player.fetch("availability_rate")
    end
  end

  test "players cannot view manager-only squad analytics" do
    travel_to(@now) { enable_plus! }

    get endpoint, headers: auth_headers(@player), as: :json

    assert_response :forbidden
  end

  test "Plus manager can update a player fitness status" do
    travel_to(@now) do
      enable_plus!
      patch "/teams/#{@team.id}/player_fitness_statuses/#{@player.id}",
            params: {
              player_fitness_status: {
                status: "injured",
                note: "Ankle assessment",
                expected_return_on: "2026-09-24"
              }
            },
            headers: auth_headers(@manager),
            as: :json

      assert_response :ok
      fitness = PlayerFitnessStatus.find_by!(team: @team, user: @player)
      assert_equal "injured", fitness.status
      assert_equal Date.new(2026, 9, 24), fitness.expected_return_on
    end
  end

  test "availability withdrawal records a selected-player dropout" do
    travel_to(@now) do
      match = @team.matches.create!(
        opponent: "Withdrawal Town",
        match_type: "league",
        location: "Home",
        kickoff_time: @now + 2.days
      )
      availability = Availability.create!(match: match, user: @player, status: "available")
      SquadSelection.create!(match: match, user: @player, selection_type: "starter", position: "ST")

      availability.update!(status: "unavailable")

      change = AvailabilityStatusChange.find_by!(match: match, user: @player)
      assert_equal "available", change.from_status
      assert_equal "unavailable", change.to_status
      assert change.was_selected?
      assert_not match.squad_selections.exists?(user: @player)
    end
  end

  private

  def completed_match(team_score:, opponent_score:)
    match = @team.matches.create!(
      opponent: "Analytics United",
      match_type: "league",
      location: "Home",
      kickoff_time: @now + 1.day
    )
    match.update_columns(
      kickoff_time: @now - 1.day,
      team_score: team_score,
      opponent_score: opponent_score,
      updated_at: @now
    )
    match.reload
  end

  def endpoint
    "/teams/#{@team.id}/squad_analytics"
  end

  def enable_plus!
    TeamEntitlementService.start_standard_trial!(team: @team, starts_at: @now)
  end

  def auth_headers(user)
    post "/users/sign_in",
         params: { user: { email: user.email, password: "Password123!" } },
         as: :json
    assert_response :ok
    { "Authorization" => response.headers.fetch("Authorization") }
  end

  def create_user(account_type)
    @sequence += 1
    user = User.create!(
      first_name: "Squad",
      last_name: "User#{@sequence}",
      account_type: account_type,
      email: "squad-analytics-#{@sequence}@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    user.update_column(:manager_verification_status, "approved") if account_type == "manager"
    user
  end
end
