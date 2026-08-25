require "test_helper"

class AvailabilitiesControllerTest <
  ActionDispatch::IntegrationTest

  setup do
    @user_sequence = 0

    @manager =
      create_user(
        account_type: "manager"
      )

    @player =
      create_user(
        account_type: "player"
      )

    @team =
      Team.create!(
        name:
          "Availability Plus FC"
      )

    TeamMembership.create!(
      user: @manager,
      team: @team,
      role: "manager",
      status: "approved",
      preferred_position: "CM"
    )

    TeamMembership.create!(
      user: @player,
      team: @team,
      role: "player",
      status: "approved",
      preferred_position: "CM"
    )

    @match =
      @team.matches.create!(
        opponent:
          "Reminder United",
        match_type: "league",
        location:
          "Hackney Marshes",
        kickoff_time:
          Time.current +
          7.days
      )

    clear_enqueued_jobs
  end

  test "free team cannot queue availability reminder" do
    token =
      authentication_token_for(
        @manager
      )

    assert_no_enqueued_jobs(
      only: AvailabilityReminderJob
    ) do
      post reminder_endpoint,
           headers: {
             "Authorization" =>
               token
           },
           as: :json
    end

    assert_response :forbidden

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      "plus_required",
      body.fetch(
        "code"
      )
    )

    assert_equal(
      "automatic_availability_reminders",
      body.fetch(
        "feature"
      )
    )

    assert_equal(
      "Automatic availability reminders",
      body.fetch(
        "feature_name"
      )
    )
  end

  test "plus trial manager can queue availability reminder" do
    TeamEntitlementService.start_standard_trial!(
      team: @team
    )

    token =
      authentication_token_for(
        @manager
      )

    assert_enqueued_with(
      job: AvailabilityReminderJob,
      args: [
        @match.id,
        @manager.id
      ]
    ) do
      post reminder_endpoint,
           headers: {
             "Authorization" =>
               token
           },
           as: :json
    end

    assert_response :accepted

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      "Availability reminder queued",
      body.fetch(
        "message"
      )
    )

    assert_equal(
      1,
      body.fetch(
        "recipients"
      )
    )
  end

  test "plus reminder does not queue when every player responded" do
    TeamEntitlementService.start_standard_trial!(
      team: @team
    )

    Availability.create!(
      match: @match,
      user: @player,
      status: "available"
    )

    token =
      authentication_token_for(
        @manager
      )

    assert_no_enqueued_jobs(
      only: AvailabilityReminderJob
    ) do
      post reminder_endpoint,
           headers: {
             "Authorization" =>
               token
           },
           as: :json
    end

    assert_response :ok

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      "All approved players have already updated their availability",
      body.fetch(
        "message"
      )
    )
  end

  test "player cannot queue reminder even when team has plus" do
    TeamEntitlementService.start_standard_trial!(
      team: @team
    )

    token =
      authentication_token_for(
        @player
      )

    assert_no_enqueued_jobs(
      only: AvailabilityReminderJob
    ) do
      post reminder_endpoint,
           headers: {
             "Authorization" =>
               token
           },
           as: :json
    end

    assert_response :forbidden

    body =
      JSON.parse(
        response.body
      )

    assert_includes(
      body.fetch(
        "error"
      ),
      "Only an approved manager"
    )
  end

  test "unauthenticated request is rejected" do
    assert_no_enqueued_jobs(
      only: AvailabilityReminderJob
    ) do
      post reminder_endpoint,
           as: :json
    end

    assert_response :unauthorized
  end

  private

  def reminder_endpoint
    "/teams/#{@team.id}/matches/#{@match.id}/availabilities/remind"
  end

  def create_user(account_type:)
    @user_sequence += 1

    user =
      User.create!(
        first_name:
          "Availability",
        last_name:
          "User#{@user_sequence}",
        account_type:
          account_type,
        email:
          "availability-user-#{@user_sequence}@example.com",
        password:
          "Password123!",
        password_confirmation:
          "Password123!"
      )

    if account_type == "manager"
      user.update_column(
        :manager_verification_status,
        "approved"
      )
    end

    user
  end

  def authentication_token_for(user)
    post "/users/sign_in",
         params: {
           user: {
             email:
               user.email,
             password:
               "Password123!"
           }
         },
         as: :json

    assert_response :ok

    token =
      response.headers[
        "Authorization"
      ]

    assert token.present?

    clear_enqueued_jobs

    token
  end
end
