require "test_helper"

class TeamFinancesFreePlusTest < ActionDispatch::IntegrationTest
  setup do
    @manager = User.create!(
      first_name: "Finance",
      last_name: "Manager",
      account_type: "manager",
      email: "finance-free-plus@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    @manager.update_column(:manager_verification_status, "approved")
    @team = Team.create!(name: "Free Finance FC", owner_user: @manager)
    TeamMembership.create!(
      team: @team,
      user: @manager,
      role: "manager",
      status: "approved",
      preferred_position: "CM"
    )

    post "/users/sign_in",
         params: { user: { email: @manager.email, password: "Password123!" } },
         as: :json
    @headers = { "Authorization" => response.headers.fetch("Authorization") }
  end

  test "Free manager can view the basic club finance ledger" do
    get "/teams/#{@team.id}/finance", headers: @headers, as: :json

    assert_response :ok
    body = JSON.parse(response.body)
    assert_equal false, body.fetch("plus_enabled")
    assert body.key?("summary")
    assert body.key?("entries")
  end

  test "Free manager can record income and expenses" do
    post "/teams/#{@team.id}/finance_entries",
         params: {
           team_finance_entry: {
             entry_type: "expense",
             category: "Pitch hire",
             description: "Home pitch",
             amount_pence: 8_000,
             occurred_on: Date.current
           }
         },
         headers: @headers,
         as: :json

    assert_response :created
    assert_equal 1, @team.team_finance_entries.expenses.count
  end

  test "Free manager sees the Plus prompt for finance analytics" do
    get "/teams/#{@team.id}/finance/analytics", headers: @headers, as: :json

    assert_response :forbidden
    body = JSON.parse(response.body)
    assert_equal "plus_required", body.fetch("code")
    assert_equal "club_finance", body.fetch("feature")
  end

  test "Plus manager can view finance analytics" do
    TeamEntitlementService.grant_founder_plus!(team: @team)

    get "/teams/#{@team.id}/finance/analytics", headers: @headers, as: :json

    assert_response :ok
    assert_equal true, JSON.parse(response.body).fetch("plus_enabled")
  end
end
