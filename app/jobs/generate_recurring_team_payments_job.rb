class GenerateRecurringTeamPaymentsJob < ApplicationJob
  queue_as :default

  def perform(on: Date.current)
    PaymentTemplate
      .active_recurring
      .where("next_run_on <= ?", on)
      .includes(team: :team_entitlement)
      .find_each do |template|
        next unless PlusAccess.allowed?(
          team: template.team,
          feature: :recurring_payments
        )

        generate_template_payments(template, on)
      end
  end

  private

  def generate_template_payments(template, on)
    players = User.joins(:team_memberships).where(
      team_memberships: {
        team_id: template.team_id,
        role: "player",
        status: "approved"
      }
    ).distinct

    MatchPayment.transaction do
      players.find_each do |player|
        payment = template.team.match_payments.create_or_find_by!(
          batch_key: "template:#{template.id}:#{on.iso8601}:user:#{player.id}"
        ) do |record|
          record.user = player
          record.requested_by = template.created_by
          record.payment_type = template.payment_type
          record.title = template.title
          record.description = template.description
          record.amount_pence = template.amount_pence
          record.due_at = on.in_time_zone.end_of_day + template.default_due_days.days
        end

        NotificationEvents.payment_requested(
          match_payment: payment,
          actor: template.created_by
        ) if payment.previously_new_record?
      end

      template.update!(next_run_on: template.next_run_on.next_month)
    end
  end
end
