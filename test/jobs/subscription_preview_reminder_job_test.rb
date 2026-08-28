require "test_helper"

class SubscriptionPreviewReminderJobTest <
  ActiveJob::TestCase

  setup do
    @manager =
      User.create!(
        first_name:
          "Preview",
        last_name:
          "Owner",
        email:
          "preview-owner@example.com",
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
          "Preview Reminder FC",
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
  end

  test "current preview creates one owner notification" do
    now =
      Time.zone.parse(
        "2026-08-28 10:00:00"
      )

    entitlement =
      TeamEntitlementService
        .start_standard_trial!(
          team:
            @team,
          starts_at:
            now
        )

        original_to_user =
      FirebasePushService.method(
        :to_user
      )

    FirebasePushService.define_singleton_method(
      :to_user
    ) do |**_arguments|
      true
    end

    begin
      assert_difference(
        -> {
          Notification
            .where(
              user:
                @manager,
              notification_type:
                "subscription_preview_reminder"
            )
            .count
        },
        1
      ) do
        SubscriptionPreviewReminderJob
          .perform_now(
            @team.id,
            entitlement
              .ends_at
              .iso8601,
            "standard_trial",
            "preview",
            7
          )
    ensure
      FirebasePushService.define_singleton_method(
        :to_user
      ) do |**arguments|
        original_to_user.call(
          **arguments
        )
      end
    end
  end
  end

  test "stale preview does not notify after paid upgrade" do
    now =
      Time.zone.parse(
        "2026-08-28 10:00:00"
      )

    old_entitlement =
      TeamEntitlementService
        .start_standard_trial!(
          team:
            @team,
          starts_at:
            now
        )

    TeamEntitlementService
      .activate_paid_plus!(
        team:
          @team,
        provider:
          "apple",
        provider_subscription_id:
          "preview-upgraded",
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

    assert_no_difference(
      -> {
        Notification
          .where(
            notification_type:
              "subscription_preview_reminder"
          )
          .count
      }
    ) do
      SubscriptionPreviewReminderJob
        .perform_now(
          @team.id,
          old_entitlement
            .ends_at
            .iso8601,
          "standard_trial",
          "preview",
          7
        )
    end
  end
end
