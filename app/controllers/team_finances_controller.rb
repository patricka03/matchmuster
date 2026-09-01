class TeamFinancesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :authorize_manager!
  before_action :require_club_finance_plus!, only: :analytics

  def show
    render json: finance_payload.merge(
      plus_enabled: PlusAccess.allowed?(team: @team, feature: :club_finance)
    ), status: :ok
  end

  def analytics
    render json: finance_payload.merge(plus_enabled: true), status: :ok
  end

  private

  def finance_payload
    manual_entries =
      @team
        .team_finance_entries
        .includes(:created_by, :match)
        .order(
          occurred_on: :desc,
          created_at: :desc
        )

    paid_match_subs =
      MatchPayment
        .joins(:match)
        .includes(:match)
        .match_subs
        .where(
          matches: {
            team_id: @team.id
          },
          status: "paid"
        )
        .to_a

    match_sub_income =
      paid_match_subs.sum do |payment|
        payment.amount_paid_pence - payment.refunded_amount_pence
      end

    manual_income =
      manual_entries.income.sum(:amount_pence)

    expenses =
      manual_entries.expenses.sum(:amount_pence)

    total_income = match_sub_income + manual_income
    balance = total_income - expenses

    {
      summary: {
        match_sub_income_pence: match_sub_income,
        manual_income_pence: manual_income,
        total_income_pence: total_income,
        total_expenses_pence: expenses,
        balance_pence: balance,
        position: finance_position(balance)
      },
      entries:
        manual_entries.map {
          |entry| finance_entry_json(entry)
        },
      match_subs: match_sub_rows(paid_match_subs)
    }
  end

  def set_team
    @team = Team.find(params[:team_id])
  end

  def authorize_manager!
    membership =
      current_user.team_memberships.find_by(
        team_id: @team.id,
        role: "manager",
        status: "approved"
      )

    return if current_user.account_type == "manager" &&
              current_user.manager_verification_status == "approved" &&
              membership

    render json: {
      error: "Only an approved team manager can view club finances."
    }, status: :forbidden
  end

  def require_club_finance_plus!
    require_plus!(
      team: @team,
      feature: :club_finance
    )
  end

  def finance_position(balance)
    return "surplus" if balance.positive?
    return "deficit" if balance.negative?

    "break_even"
  end

  def finance_entry_json(entry)
    {
      id: entry.id,
      entry_type: entry.entry_type,
      category: entry.category,
      description: entry.description,
      amount_pence: entry.amount_pence,
      occurred_on: entry.occurred_on,
      match_id: entry.match_id,
      created_by:
        entry.created_by ? {
          id: entry.created_by.id,
          first_name: entry.created_by.first_name,
          last_name: entry.created_by.last_name
        } : nil,
      created_at: entry.created_at,
      updated_at: entry.updated_at
    }
  end

  def match_sub_rows(payments)
    payments
      .group_by(&:match_id)
      .values
      .map do |group|
        match = group.first.match

        {
          match_id: match.id,
          opponent: match.opponent,
          kickoff_time: match.kickoff_time,
          amount_pence: group.sum do |payment|
            payment.amount_paid_pence - payment.refunded_amount_pence
          end,
          payments_received: group.length,
          occurred_on:
            (
              group.map(&:paid_at).compact.max ||
              match.kickoff_time
            )&.to_date
        }
      end
      .sort_by {
        |row|
        row[:occurred_on] || Date.new(1970, 1, 1)
      }
      .reverse
  end
end
