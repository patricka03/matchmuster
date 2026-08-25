require "test_helper"

class RecurringTrainingsControllerTest <
  ActionDispatch::IntegrationTest

  setup do
    @user_sequence = 0

    @manager =
      create_user(
        account_type:
          "manager"
      )

    @team =
      Team.create!(
        name:
          "Recurring Controller FC"
      )

    TeamMembership.create!(
      user: @manager,
      team: @team,
      role: "manager",
      status: "approved",
      preferred_position: "CM"
    )

    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )
  end

  test "Plus manager can create recurring training" do
    travel_to(
      @now
    ) do
      enable_plus!

      token =
        authentication_token_for(
          @manager
        )

      assert_difference(
        "Training.count",
        3
      ) do
        post recurring_endpoint,
             params:
               recurring_payload,
             headers: {
               "Authorization" =>
                 token
             },
             as: :json
      end

      assert_response :created

      body =
        JSON.parse(
          response.body
        )

      assert_equal(
        "weekly",
        body.fetch(
          "frequency"
        )
      )

      assert_equal(
        3,
        body.fetch(
          "occurrences"
        )
      )

      assert_match(
        Training::RECURRENCE_GROUP_ID_FORMAT,
        body.fetch(
          "recurrence_group_id"
        )
      )

      trainings =
        body.fetch(
          "trainings"
        )

      assert_equal(
        [
          1,
          2,
          3
        ],
        trainings.map do |training|
          training.fetch(
            "recurrence_sequence"
          )
        end
      )
    end
  end

  test "Free manager is blocked from recurring training" do
    token =
      authentication_token_for(
        @manager
      )

    assert_no_difference(
      "Training.count"
    ) do
      post recurring_endpoint,
           params:
             recurring_payload,
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
      "recurring_training",
      body.fetch(
        "feature"
      )
    )
  end

  test "Free manager can still create one-off training" do
    token =
      authentication_token_for(
        @manager
      )

    assert_difference(
      "Training.count",
      1
    ) do
      post one_off_endpoint,
           params: {
             training:
               training_payload
           },
           headers: {
             "Authorization" =>
               token
           },
           as: :json
    end

    assert_response :created

    training =
      @team
        .trainings
        .last

    assert_not(
      training.recurring?
    )
  end

  test "invalid recurring schedule creates no sessions" do
    travel_to(
      @now
    ) do
      enable_plus!

      token =
        authentication_token_for(
          @manager
        )

      payload =
        recurring_payload

      payload
        .fetch(
          :recurrence
        )[
          :occurrences
        ] = 1

      assert_no_difference(
        "Training.count"
      ) do
        post recurring_endpoint,
             params: payload,
             headers: {
               "Authorization" =>
                 token
             },
             as: :json
      end

      assert_response :unprocessable_entity

      body =
        JSON.parse(
          response.body
        )

      assert_equal(
        "invalid_recurring_training",
        body.fetch(
          "code"
        )
      )
    end
  end

  test "player cannot create recurring training" do
    player =
      create_user(
        account_type:
          "player"
      )

    TeamMembership.create!(
      user: player,
      team: @team,
      role: "player",
      status: "approved",
      preferred_position: "CM"
    )

    token =
      authentication_token_for(
        player
      )

    assert_no_difference(
      "Training.count"
    ) do
      post recurring_endpoint,
           params:
             recurring_payload,
           headers: {
             "Authorization" =>
               token
           },
           as: :json
    end

    assert_response :forbidden

    refute_includes(
      response.body,
      "plus_required"
    )
  end

  test "manager from another team cannot create recurring training" do
    other_manager =
      create_user(
        account_type:
          "manager"
      )

    token =
      authentication_token_for(
        other_manager
      )

    assert_no_difference(
      "Training.count"
    ) do
      post recurring_endpoint,
           params:
             recurring_payload,
           headers: {
             "Authorization" =>
               token
           },
           as: :json
    end

    assert_response :forbidden
  end

  test "unauthenticated recurring request is rejected" do
    assert_no_difference(
      "Training.count"
    ) do
      post recurring_endpoint,
           params:
             recurring_payload,
           as: :json
    end

    assert_response :unauthorized
  end

  test "missing team returns not found" do
    token =
      authentication_token_for(
        @manager
      )

    post "/teams/999999/trainings/recurring",
         params:
           recurring_payload,
         headers: {
           "Authorization" =>
             token
         },
         as: :json

    assert_response :not_found
  end

  private

  def recurring_endpoint
    "/teams/#{@team.id}/trainings/recurring"
  end

  def one_off_endpoint
    "/teams/#{@team.id}/trainings"
  end

  def recurring_payload
    {
      training:
        training_payload,
      recurrence: {
        frequency:
          "weekly",
        occurrences: 3
      }
    }
  end

  def training_payload
    {
      title:
        "Thursday Training",
      location:
        "Training Ground",
      description:
        "Recurring first-team session",
      meet_time:
        @now +
        4.days -
        30.minutes,
      starts_at:
        @now +
        4.days
    }
  end

  def enable_plus!
    TeamEntitlementService.start_standard_trial!(
      team: @team,
      starts_at: @now
    )
  end

  def create_user(account_type:)
    @user_sequence += 1

    user =
      User.create!(
        first_name:
          "Recurring",
        last_name:
          "User#{@user_sequence}",
        account_type:
          account_type,
        email:
          "recurring-user-#{@user_sequence}@example.com",
        password:
          "Password123!",
        password_confirmation:
          "Password123!"
      )

    if account_type ==
       "manager"
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

    token
  end
end
