require "test_helper"

class MatchPaymentTest < ActiveSupport::TestCase
  setup do
    @manager = create_user("manager", "payment-model-manager@example.com")
    @player = create_user("player", "payment-model-player@example.com")
    @team = Team.create!(name: "Payment Model FC")
    create_membership(@manager, "manager")
    create_membership(@player, "player")

    travel_to(Time.zone.parse("2026-09-01 12:00:00")) do
      @match = @team.matches.create!(
        opponent: "Model Athletic",
        match_type: "league",
        location: "Home",
        kickoff_time: 2.days.from_now
      )
    end
  end

  test "legacy Match Subs automatically inherit team and title" do
    payment = MatchPayment.create!(
      user: @player,
      match: @match,
      amount_pence: 1_000
    )

    assert_equal @team, payment.team
    assert_equal "match_sub", payment.payment_type
    assert_equal "Match Subs", payment.title
  end

  test "non-match team payment is supported" do
    payment = @team.match_payments.create!(
      user: @player,
      requested_by: @manager,
      payment_type: "membership_fee",
      title: "September membership",
      amount_pence: 2_000,
      due_at: 7.days.from_now
    )

    assert_nil payment.match
    assert_equal 2_000, payment.amount_outstanding_pence
  end

  test "legacy Match Subs still allow only one request per player and match" do
    MatchPayment.create!(
      user: @player,
      match: @match,
      amount_pence: 1_000
    )

    duplicate = MatchPayment.new(
      user: @player,
      match: @match,
      amount_pence: 1_000
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user], "already has a Match Subs request for this match"
  end

  test "partial payments preserve the outstanding balance" do
    payment = @team.match_payments.create!(
      user: @player,
      payment_type: "kit_payment",
      title: "Away shirt",
      amount_pence: 3_000
    )

    payment.record_payment!(amount_pence: 1_000, method: "cash")

    assert_equal "partially_paid", payment.status
    assert_equal 1_000, payment.amount_paid_pence
    assert_equal 2_000, payment.amount_outstanding_pence
    assert_nil payment.paid_at
  end

  test "player must belong to the payment team" do
    outsider = create_user("player", "payment-model-outsider@example.com")
    payment = @team.match_payments.new(
      user: outsider,
      payment_type: "other",
      title: "Team charge",
      amount_pence: 500
    )

    assert_not payment.valid?
    assert_includes payment.errors[:user], "must be an approved player for this team"
  end

  private

  def create_user(account_type, email)
    user = User.create!(
      first_name: account_type.capitalize,
      last_name: "Payment",
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
end
