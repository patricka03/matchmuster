require "test_helper"

class TeamPaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @manager = create_user("manager", "payments-manager@example.com")
    @player = create_user("player", "payments-player@example.com")
    @second_player = create_user("player", "payments-player-two@example.com")
    @team = Team.create!(name: "Payments Controller FC", owner_user: @manager)
    create_membership(@manager, "manager")
    create_membership(@player, "player")
    create_membership(@second_player, "player")

    travel_to(Time.zone.parse("2026-09-01 12:00:00")) do
      @match = @team.matches.create!(
        opponent: "Payments United",
        match_type: "league",
        location: "Home",
        kickoff_time: 3.days.from_now
      )
    end

    @manager_headers = auth_headers(@manager)
    @player_headers = auth_headers(@player)
  end

  test "Free manager is prompted for Plus when creating a team payment" do
    post team_payments_endpoint,
         params: {
           payment: {
             payment_type: "membership_fee",
             title: "September membership",
             amount_pence: 1_500,
             recipient_scope: "all_players",
             due_at: 7.days.from_now
           }
         },
         headers: @manager_headers,
         as: :json

    assert_response :forbidden
    assert_equal "team_payments", JSON.parse(response.body).fetch("feature")
    assert_equal 0, @team.match_payments.where(payment_type: "membership_fee").count
  end

  test "Plus manager can send a legitimate team payment to all players" do
    enable_plus!

    post team_payments_endpoint,
         params: {
           payment: {
             payment_type: "membership_fee",
             title: "September membership",
             amount_pence: 1_500,
             recipient_scope: "all_players",
             due_at: 7.days.from_now
           }
         },
         headers: @manager_headers,
         as: :json

    assert_response :created
    assert_equal 2, JSON.parse(response.body).fetch("created_count")
    assert_equal 2, @team.match_payments.where(payment_type: "membership_fee").count
  end

  test "player sees only their own team payments" do
    create_payment(@player, "Player one")
    create_payment(@second_player, "Player two")

    get team_payments_endpoint, headers: @player_headers, as: :json

    assert_response :ok
    rows = JSON.parse(response.body).fetch("payments")
    assert_equal [@player.id], rows.map { |row| row.fetch("user_id") }.uniq
  end

  test "manager can record a partial cash payment" do
    enable_plus!
    payment = create_payment(@player, "Kit contribution", amount_pence: 2_000)

    post "#{team_payments_endpoint}/#{payment.id}/record_payment",
         params: { payment: { amount_pence: 750, payment_method: "cash" } },
         headers: @manager_headers,
         as: :json

    assert_response :ok
    payment.reload
    assert_equal "partially_paid", payment.status
    assert_equal 750, payment.amount_paid_pence
  end

  test "player can request cash confirmation" do
    payment = create_payment(@player, "Training fee")

    post "#{team_payments_endpoint}/#{payment.id}/request_cash_confirmation",
         headers: @player_headers,
         as: :json

    assert_response :ok
    assert_equal "cash_pending", payment.reload.status
    assert payment.cash_confirmation_requested_at.present?
  end

  test "Free manager is gated from payment analytics" do
    get "#{team_payments_endpoint}/summary",
        headers: @manager_headers,
        as: :json

    assert_response :forbidden
    assert_equal "payment_analytics", JSON.parse(response.body).fetch("feature")
  end

  test "disciplinary record can create an attached player fine" do
    enable_plus!
    post "/teams/#{@team.id}/disciplinary_records",
         params: {
           disciplinary_record: {
             match_id: @match.id,
             player_id: @player.id,
             card_type: "yellow",
             incident_minute: 42,
             reason: "Unsporting behaviour",
             suspension_matches: 0,
             fine_amount_pence: 1_200,
             fine_due_at: 7.days.from_now
           }
         },
         headers: @manager_headers,
         as: :json

    assert_response :created
    record = @team.disciplinary_records.last
    assert_equal "yellow", record.card_type
    assert_equal "yellow_card_fine", record.match_payment.payment_type
    assert_equal 1_200, record.match_payment.amount_pence
  end

  test "card can be recorded without creating a fine" do
    enable_plus!
    post "/teams/#{@team.id}/disciplinary_records",
         params: {
           disciplinary_record: {
             match_id: @match.id,
             player_id: @player.id,
             card_type: "straight_red",
             suspension_matches: 2
           }
         },
         headers: @manager_headers,
         as: :json

    assert_response :created
    record = @team.disciplinary_records.last
    assert_nil record.match_payment
    assert_equal 2, record.suspension_matches_remaining
  end

  private

  def team_payments_endpoint
    "/teams/#{@team.id}/payments"
  end

  def enable_plus!
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: Time.current
    )
  end

  def create_payment(player, title, amount_pence: 1_000)
    @team.match_payments.create!(
      user: player,
      requested_by: @manager,
      payment_type: "other",
      title: title,
      amount_pence: amount_pence,
      due_at: 7.days.from_now
    )
  end

  def create_user(account_type, email)
    user = User.create!(
      first_name: account_type.capitalize,
      last_name: "Payments",
      account_type: account_type,
      email: email,
      password: "Password123!",
      password_confirmation: "Password123!"
    )
    user.update_column(:manager_verification_status, "approved") if account_type == "manager"
    user
  end

  def create_membership(user, role)
    TeamMembership.create!(
      team: @team,
      user: user,
      role: role,
      status: "approved",
      preferred_position: "CM"
    )
  end

  def auth_headers(user)
    post "/users/sign_in",
         params: { user: { email: user.email, password: "Password123!" } },
         as: :json
    assert_response :ok
    { "Authorization" => response.headers.fetch("Authorization") }
  end
end
