require "test_helper"

class PlusManagerFeatureGatesTest <
  ActionDispatch::IntegrationTest

  setup do
    @user_sequence = 0

    @manager =
      create_user(
        account_type:
          "manager"
      )

    @player =
      create_user(
        account_type:
          "player"
      )

    @team =
      Team.create!(
        name:
          "Plus Feature Gates FC"
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

    @now =
      Time.zone.parse(
        "2026-09-01 12:00:00"
      )

    travel_to(
      @now
    ) do
      @match =
        @team
          .matches
          .create!(
            opponent:
              "Subscription Athletic",
            match_type:
              "league",
            location:
              "Feature Gate Stadium",
            kickoff_time:
              @now +
              7.days
          )

      @post =
        @team
          .posts
          .create!(
            user: @manager,
            title:
              "Saturday Tactical Briefing",
            content:
              "Keep our defensive shape compact.",
            post_type:
              "tactical"
          )
    end
  end

  test "Free manager cannot access payment analytics summary" do
    token =
      authentication_token_for(
        @manager
      )

    get payment_summary_endpoint,
        headers: {
          "Authorization" =>
            token
        },
        as: :json

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
      "payment_analytics",
      body.fetch(
        "feature"
      )
    )
  end

  test "Plus manager can access payment analytics summary" do
    travel_to(
      @now
    ) do
      enable_plus!

      token =
        authentication_token_for(
          @manager
        )

      get payment_summary_endpoint,
          headers: {
            "Authorization" =>
              token
          },
          as: :json

      assert_response :ok

      body =
        JSON.parse(
          response.body
        )

      assert_equal(
        0,
        body.fetch(
          "total_paid_pence"
        )
      )

      assert_equal(
        0,
        body.fetch(
          "payment_count"
        )
      )
    end
  end

  test "ordinary match payment list remains available on Free" do
    token =
      authentication_token_for(
        @manager
      )

    get match_payments_endpoint,
        headers: {
          "Authorization" =>
            token
        },
        as: :json

    assert_response :ok

    assert_equal(
      [],
      JSON.parse(
        response.body
      )
    )
  end

  test "Free manager cannot inspect tactical read receipts" do
    token =
      authentication_token_for(
        @manager
      )

    get post_reads_endpoint,
        headers: {
          "Authorization" =>
            token
        },
        as: :json

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
      "tactical_read_receipts",
      body.fetch(
        "feature"
      )
    )
  end

  test "read recording remains Free and Plus manager can inspect it" do
    travel_to(
      @now
    ) do
      player_token =
        authentication_token_for(
          @player
        )

      post post_reads_endpoint,
           headers: {
             "Authorization" =>
               player_token
           },
           as: :json

      assert_response :created

      enable_plus!

      manager_token =
        authentication_token_for(
          @manager
        )

      get post_reads_endpoint,
          headers: {
            "Authorization" =>
              manager_token
          },
          as: :json

      assert_response :ok

      reads =
        JSON.parse(
          response.body
        )

      assert_equal(
        1,
        reads.length
      )

      assert_equal(
        @player.id,
        reads
          .first
          .fetch(
            "user"
          )
          .fetch(
            "id"
          )
      )
    end
  end

  test "player cannot probe manager premium endpoints" do
    token =
      authentication_token_for(
        @player
      )

    get post_reads_endpoint,
        headers: {
          "Authorization" =>
            token
        },
        as: :json

    assert_response :forbidden

    refute_includes(
      response.body,
      "plus_required"
    )

    get payment_summary_endpoint,
        headers: {
          "Authorization" =>
            token
        },
        as: :json

    assert_response :forbidden

    refute_includes(
      response.body,
      "plus_required"
    )
  end

  test "team awards remain available to players on Free" do
    token =
      authentication_token_for(
        @player
      )

    get "/teams/#{@team.id}/awards",
        headers: {
          "Authorization" =>
            token
        },
        as: :json

    assert_response :ok

    body =
      JSON.parse(
        response.body
      )

    assert body.key?(
      "month"
    )

    assert body.key?(
      "season"
    )
  end

  test "match statistics management remains available on Free" do
    token =
      authentication_token_for(
        @manager
      )

    get "/teams/#{@team.id}/matches/#{@match.id}/match_player_stats",
        headers: {
          "Authorization" =>
            token
        },
        as: :json

    assert_response :ok

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      [],
      body.fetch(
        "players"
      )
    )
  end

  private

  def payment_summary_endpoint
    "/teams/#{@team.id}/matches/#{@match.id}/match_payments/summary"
  end

  def match_payments_endpoint
    "/teams/#{@team.id}/matches/#{@match.id}/match_payments"
  end

  def post_reads_endpoint
    "/teams/#{@team.id}/posts/#{@post.id}/post_reads"
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
          "Feature",
        last_name:
          "User#{@user_sequence}",
        account_type:
          account_type,
        email:
          "plus-gate-user-#{@user_sequence}@example.com",
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
