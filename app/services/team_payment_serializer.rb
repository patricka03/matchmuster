class TeamPaymentSerializer
  class << self
    def call(payment)
      {
        id: payment.id,
        team_id: payment.team_id,
        match_id: payment.match_id,
        user_id: payment.user_id,
        requested_by_id: payment.requested_by_id,
        payment_type: payment.payment_type,
        type_label: payment.type_label,
        title: payment.title,
        description: payment.description,
        amount_pence: payment.amount_pence,
        amount_paid_pence: payment.amount_paid_pence,
        amount_outstanding_pence: payment.amount_outstanding_pence,
        refunded_amount_pence: payment.refunded_amount_pence,
        status: payment.status,
        display_status: display_status(payment),
        payment_method: payment.payment_method,
        due_at: payment.due_at,
        overdue: payment.overdue?,
        paid_at: payment.paid_at,
        refunded_at: payment.refunded_at,
        waived_at: payment.waived_at,
        cancelled_at: payment.cancelled_at,
        viewed_at: payment.viewed_at,
        cash_confirmation_requested_at:
          payment.cash_confirmation_requested_at,
        league_settled_at: payment.league_settled_at,
        stripe_payment_intent_id:
          payment.stripe_payment_intent_id,
        user: user_json(payment.user),
        match: match_json(payment.match),
        disciplinary_record:
          discipline_json(payment.disciplinary_record),
        created_at: payment.created_at,
        updated_at: payment.updated_at
      }
    end

    private

    def display_status(payment)
      return "overdue" if payment.overdue?

      payment.status
    end

    def user_json(user)
      return nil unless user

      {
        id: user.id,
        first_name: user.first_name,
        last_name: user.last_name
      }
    end

    def match_json(match)
      return nil unless match

      {
        id: match.id,
        opponent: match.opponent,
        kickoff_time: match.kickoff_time
      }
    end

    def discipline_json(record)
      return nil unless record

      {
        id: record.id,
        card_type: record.card_type,
        incident_minute: record.incident_minute,
        reason: record.reason,
        notes: record.notes,
        evidence_url: record.evidence_url,
        suspension_matches: record.suspension_matches,
        suspension_matches_remaining:
          record.suspension_matches_remaining,
        appeal_status: record.appeal_status
      }
    end
  end
end
