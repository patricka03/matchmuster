require "test_helper"

class Developers::LaunchClubsControllerTest <
  ActionDispatch::IntegrationTest

  setup do
    @developer =
      Developer.create!(
        email:
          "launch-admin@example.com",
        password:
          "Password123!",
        password_confirmation:
          "Password123!"
      )

    @manager =
      User.create!(
        first_name:
          "Launch",
        last_name:
          "Manager",
        email:
          "launch-manager@example.com",
        account_type:
          "manager",
        password:
          "Password123!",
        password_confirmation:
          "Password123!"
      )

    @manager.update_column(
      :manager_verification_status,
      "approved"
    )

    @team =
      Team.create!(
        name:
          "Launch Test FC",
        owner_user:
          @manager
      )

    TeamMembership.create!(
      team:
        @team,
      user:
        @manager,
      role:
        "manager",
      status:
        "approved",
      preferred_position:
        "CM"
    )

    @developer_token =
      developer_token
  end

  test "developer can list launch clubs" do
    get "/developer/launch_clubs",
        headers: {
          "Authorization" =>
            @developer_token
        },
        as: :json

    assert_response :ok

    body =
      JSON.parse(
        response.body
      )

    assert_equal(
      20,
      body.fetch(
        "launch_club_target"
      )
    )

    team =
      body
        .fetch("teams")
        .find do |item|
          item.fetch("id") ==
            @team.id
        end

    assert team

    assert_equal(
      false,
      team.fetch(
        "launch_club"
      )
    )
  end

  test "launch club replaces preview instead of stacking" do
    preview_start =
      Time.zone.parse(
        "2026-08-20 10:00:00"
      )

    TeamEntitlementService
      .start_standard_trial!(
        team:
          @team,
        starts_at:
          preview_start
      )

    travel_to(
      preview_start +
      5.days
    ) do
      patch "/developer/launch_clubs/#{@team.id}/grant",
            headers: {
              "Authorization" =>
                @developer_token
            },
            as: :json

      assert_response :ok

      team =
        @team.reload

      entitlement =
        team.team_entitlement

      assert team.launch_club?

      assert_equal(
        "founder",
        entitlement.source
      )

      assert_equal(
        preview_start.to_i,
        entitlement
          .starts_at
          .to_i
      )

      assert_equal(
        (
          preview_start +
          8.weeks
        ).to_i,
        entitlement
          .ends_at
          .to_i
      )
    end
  end

  test "launch club identity does not overwrite active paid plus" do
    now =
      Time.zone.parse(
        "2026-08-28 10:00:00"
      )

    TeamEntitlementService
      .activate_paid_plus!(
        team:
          @team,
        provider:
          "apple",
        provider_subscription_id:
          "launch-paid-subscription",
        billing_period:
          "monthly",
        provider_product_id:
          "matchmuster_plus_monthly",
        starts_at:
          now,
        ends_at:
          now + 1.month,
        auto_renews:
          true
      )

    patch "/developer/launch_clubs/#{@team.id}/grant",
          headers: {
            "Authorization" =>
              @developer_token
          },
          as: :json

    assert_response :ok

    team =
      @team.reload

    assert team.launch_club?

    assert_equal(
      "apple",
      team
        .team_entitlement
        .source
    )
  end

  private

  def developer_token
    post "/developer/login",
         params: {
           developer: {
             email:
               @developer.email,
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
