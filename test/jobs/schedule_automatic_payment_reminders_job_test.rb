require "test_helper"

class ScheduleAutomaticPaymentRemindersJobTest <
  ActiveJob::TestCase

  setup do
    @team =
      Team.create!(
        name:
          "Payment Scheduler FC"
      )

    @player =
      User.create!(
        first_name: "Scheduled",
        last_name: "Player",
        account_type: "player",
        email:
          "scheduled-payment-player@example.com",
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

    clear_enqueued_jobs
  end

  test "queues pending payment inside reminder window" do
    travel_to(@now) do
      start_plus_trial

      payment =
        create_payment(
          kickoff_time:
            @now + 12.hours
        )

      clear_enqueued_jobs

      assert_enqueued_with(
        job:
          AutomaticMatchPaymentReminderJob,
        args: [
          payment.id
        ]
      ) do
        perform_scheduler
      end
    end
  end

  test "does not queue payment outside reminder window" do
    travel_to(@now) do
      start_plus_trial

      create_payment(
        kickoff_time:
          @now + 2.days
      )

      clear_enqueued_jobs

      assert_no_enqueued_jobs(
        only:
          AutomaticMatchPaymentReminderJob
      ) do
        perform_scheduler
      end
    end
  end

  test "does not queue paid payment" do
    travel_to(@now) do
      start_plus_trial

      payment =
        create_payment(
          kickoff_time:
            @now + 12.hours
        )

      payment.update!(
        status: "paid",
        paid_at: Time.current
      )

      clear_enqueued_jobs

      assert_no_enqueued_jobs(
        only:
          AutomaticMatchPaymentReminderJob
      ) do
        perform_scheduler
      end
    end
  end

  test "does not queue cancelled fixture payment" do
    travel_to(@now) do
      start_plus_trial

      payment =
        create_payment(
          kickoff_time:
            @now + 12.hours
        )

      payment.match.update!(
        cancelled_at:
          Time.current
      )

      clear_enqueued_jobs

      assert_no_enqueued_jobs(
        only:
          AutomaticMatchPaymentReminderJob
      ) do
        perform_scheduler
      end
    end
  end

  test "queues each eligible pending payment" do
    travel_to(@now) do
      start_plus_trial

      first_payment =
        create_payment(
          kickoff_time:
            @now + 10.hours
        )

      second_match =
        @team.matches.create!(
          opponent:
            "Second Payment FC",
          match_type: "league",
          location:
            "Victoria Park",
          kickoff_time:
            @now + 20.hours
        )

      second_payment =
        MatchPayment.create!(
          match: second_match,
          user: @player,
          amount_pence: 1_500
        )

      clear_enqueued_jobs

      assert_enqueued_jobs(
        2,
        only:
          AutomaticMatchPaymentReminderJob
      ) do
        perform_scheduler
      end

      queued_payment_ids =
        enqueued_jobs
          .select do |job|
            job.fetch(
              :job
            ) ==
              AutomaticMatchPaymentReminderJob
          end
          .map do |job|
            job.fetch(
              :args
            ).first
          end

      assert_equal(
        [
          first_payment.id,
          second_payment.id
        ].sort,
        queued_payment_ids.sort
      )
    end
  end

  test "does not queue payment for free team" do
    travel_to(@now) do
      create_payment(
        kickoff_time:
          @now + 12.hours
      )

      clear_enqueued_jobs

      assert_no_enqueued_jobs(
        only:
          AutomaticMatchPaymentReminderJob
      ) do
        perform_scheduler
      end
    end
  end

  private

  def create_payment(kickoff_time:)
    match =
      @team.matches.create!(
        opponent:
          "Scheduled Payment FC",
        match_type: "league",
        location:
          "Hackney Marshes",
        kickoff_time:
          kickoff_time
      )

    MatchPayment.create!(
      match: match,
      user: @player,
      amount_pence: 1_250
    )
  end

  def perform_scheduler
    ScheduleAutomaticPaymentRemindersJob.perform_now(
      now: @now
    )
  end

  def start_plus_trial
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @now
    )
  end
end
