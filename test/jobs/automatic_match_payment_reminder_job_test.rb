require "test_helper"

class AutomaticMatchPaymentReminderJobTest <
  ActiveJob::TestCase

  setup do
    @team =
      Team.create!(
        name:
          "Payment Reminder FC"
      )

    @player =
      User.create!(
        first_name: "Payment",
        last_name: "Player",
        account_type: "player",
        email:
          "automatic-payment-player@example.com",
        password: "Password123!",
        password_confirmation:
          "Password123!"
      )

    TeamMembership.create!(
      team: @team,
      user: @player,
      role: "player",
      status: "approved",
      preferred_position: "CM"
    )

    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "free team does not receive automatic payment reminder" do
    travel_to(@now) do
      payment =
        create_payment

      assert_no_difference(
        "@player.notifications.count"
      ) do
        perform_reminder(
          payment
        )
      end
    end
  end

  test "Plus team receives reminder for pending payment" do
    travel_to(@now) do
      start_plus_trial

      payment =
        create_payment

      assert_difference(
        "@player.notifications.count",
        1
      ) do
        perform_reminder(
          payment
        )
      end

      notification =
        @player
          .notifications
          .order(created_at: :desc)
          .first

      assert_equal(
        "match_payment_reminder",
        notification.notification_type
      )

      assert_equal(
        payment.id,
        notification.match_payment_id
      )

      assert_equal(
        payment.match_id,
        notification.match_id
      )

      assert_equal(
        "Your £12.50 match payment for the fixture against Payment United is still outstanding.",
        notification.message
      )
    end
  end

  test "paid payment is not reminded" do
    travel_to(@now) do
      start_plus_trial

      payment =
        create_payment

      payment.update!(
        status: "paid",
        paid_at: Time.current
      )

      assert_no_difference(
        "@player.notifications.count"
      ) do
        perform_reminder(
          payment
        )
      end
    end
  end

  test "waived payment is not reminded" do
    travel_to(@now) do
      start_plus_trial

      payment =
        create_payment

      payment.update!(
        status: "waived"
      )

      assert_no_difference(
        "@player.notifications.count"
      ) do
        perform_reminder(
          payment
        )
      end
    end
  end

  test "cancelled fixture payment is not reminded" do
    travel_to(@now) do
      start_plus_trial

      payment =
        create_payment

      payment.match.update!(
        cancelled_at:
          Time.current
      )

      assert_no_difference(
        "@player.notifications.count"
      ) do
        perform_reminder(
          payment
        )
      end
    end
  end

  test "payment is not reminded after kickoff" do
    payment = nil

    travel_to(@now) do
      start_plus_trial

      payment =
        create_payment
    end

    travel_to(
      payment.match.kickoff_time +
      1.minute
    ) do
      assert_no_difference(
        "@player.notifications.count"
      ) do
        perform_reminder(
          payment
        )
      end
    end
  end

  test "repeated execution is idempotent" do
    travel_to(@now) do
      start_plus_trial

      payment =
        create_payment

      assert_difference(
        "@player.notifications.count",
        1
      ) do
        2.times do
          perform_reminder(
            payment
          )
        end
      end
    end
  end

  private

  def create_payment
    match =
      @team.matches.create!(
        opponent:
          "Payment United",
        match_type: "league",
        location:
          "Hackney Marshes",
        kickoff_time:
          @now +
          12.hours
      )

    clear_enqueued_jobs

    MatchPayment.create!(
      match: match,
      user: @player,
      amount_pence: 1_250
    )
  end

  def start_plus_trial
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @now
    )
  end

  def perform_reminder(payment)
    AutomaticMatchPaymentReminderJob.perform_now(
      payment.id
    )
  end
end
