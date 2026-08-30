require "test_helper"

class MatchLateStatusesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = User.create!(
      first_name: "Matchday",
      last_name: "Manager",
      account_type: "manager",
      email: "matchday-manager@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @manager.update_column(:manager_verification_status, "approved")
    @team = Team.create!(name: "Matchday Window FC")
    TeamMembership.create!(
      user: @manager,
      team: @team,
      role: "manager",
      status: "approved",
      preferred_position: "CM"
    )
    @kickoff = Time.zone.parse("2026-09-12 15:00:00")

    travel_to(@kickoff - 1.day) do
      @match = @team.matches.create!(
        opponent: "Window United",
        match_type: "league",
        location: "Home",
        kickoff_time: @kickoff
      )
    end

    @headers = auth_headers(@manager)
  end

  test "matchday live remains visible until two hours after kickoff" do
    travel_to(@kickoff + 1.hour + 59.minutes) do
      get endpoint, headers: @headers, as: :json

      assert_response :ok
      body = JSON.parse(response.body)
      assert_equal @match.id, body.dig("match", "id")
      assert body.fetch("reporting_open")
    end
  end

  test "matchday live is removed at two hours after kickoff" do
    travel_to(@kickoff + 2.hours) do
      get endpoint, headers: @headers, as: :json

      assert_response :ok
      body = JSON.parse(response.body)
      assert_nil body.fetch("match")
      assert_equal [], body.fetch("statuses")
      assert_not body.fetch("reporting_open")
    end
  end

  private

  def endpoint
    "/teams/#{@team.id}/matchday/late_statuses"
  end

  def auth_headers(user)
    post "/users/sign_in",
         params: { user: { email: user.email, password: "Password123!" } },
         as: :json
    assert_response :ok
    { "Authorization" => response.headers.fetch("Authorization") }
  end
end
