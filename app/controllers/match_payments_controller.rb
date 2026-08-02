class MatchPaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :set_match
  before_action :authorize_team_member!
  before_action :set_match_payment, only: %i[show update destroy]
  before_action :authorize_manager!, only: %i[create update destroy summary]
  before_action :authorize_payment_view!, only: %i[show]

  def index
    @match_payments =
      if approved_manager?
        @match.match_payments.includes(:user)
      else
        @match.match_payments.where(user: current_user)
      end

    render json: @match_payments.as_json(
      include: {
        user: {
          only: %i[id first_name last_name]
        }
      }
    ), status: :ok
  end

  def show
    render json: @match_payment.as_json(
      include: {
        user: {
          only: %i[id first_name last_name]
        }
      }
    ), status: :ok
  end

  def create
    player_membership = @team.team_memberships.find_by(
      user_id: create_payment_params[:user_id],
      role: "player",
      status: "approved"
    )

    unless player_membership
      return render json: {
        error: "Payment can only be requested from an approved player in this team"
      }, status: :unprocessable_entity
    end

    @match_payment = @match.match_payments.new(create_payment_params)

    if @match_payment.save
      create_match_payment_notification

      render json: @match_payment, status: :created
    else
      render json: {
        errors: @match_payment.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    new_status = update_payment_params[:status]

    unless %w[pending paid waived].include?(new_status)
      return render json: {
        error: "Status must be pending, paid or waived"
      }, status: :unprocessable_entity
    end

    attributes = {
      status: new_status,
      paid_at: new_status == "paid" ? Time.current : nil
    }

    if @match_payment.update(attributes)
      if @match_payment.saved_change_to_status?
        create_paid_notification if @match_payment.status == "paid"
        create_waived_notification if @match_payment.status == "waived"
      end

      render json: @match_payment, status: :ok
    else
      render json: {
        errors: @match_payment.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    @match_payment.destroy

    head :no_content
  end

  def summary
  payments = @match.match_payments

  render json: {
    total_requested_pence: payments.sum(:amount_pence),
    total_paid_pence: payments.where(status: "paid").sum(:amount_pence),
    total_pending_pence: payments.where(status: "pending").sum(:amount_pence),
    total_waived_pence: payments.where(status: "waived").sum(:amount_pence),
    payment_count: payments.count
    }, status: :ok
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_match
    @match = @team.matches.find(params[:match_id])
  end

  def set_match_payment
    @match_payment = @match.match_payments.find(params[:id])
  end

  def authorize_team_member!
    approved_member = current_user.team_memberships.exists?(
      team_id: @team.id,
      status: "approved"
    )

    return if approved_member

    render json: {
      error: "You are not an approved member of this team"
    }, status: :forbidden
  end

  def authorize_manager!
    return if approved_manager?

    render json: {
      error: "Only an approved team manager can manage match payments"
    }, status: :forbidden
  end

  def authorize_payment_view!
    return if approved_manager?
    return if @match_payment.user_id == current_user.id

    render json: {
      error: "You are not authorised to view this payment"
    }, status: :forbidden
  end

  def approved_manager?
    current_user.account_type == "manager" &&
      current_user.manager_verification_status == "approved" &&
      current_user.team_memberships.exists?(
        team_id: @team.id,
        role: "manager",
        status: "approved"
      )
  end

  def create_payment_params
    params.require(:match_payment).permit(
      :user_id,
      :amount_pence
    )
  end

  def update_payment_params
    params.require(:match_payment).permit(:status)
  end

  def create_match_payment_notification
    @match_payment.user.notifications.create!(
      title: "Match payment requested",
      message: "You have been requested to pay £#{formatted_amount} for the upcoming match.",
      notification_type: "match_payment_requested"
    )
  end

  def create_paid_notification
    @match_payment.user.notifications.create!(
      title: "Match payment received",
      message: "Your payment of £#{formatted_amount} has been marked as paid.",
      notification_type: "match_payment_paid"
    )
  end

  def create_waived_notification
    @match_payment.user.notifications.create!(
      title: "Match payment waived",
      message: "Your match payment of £#{formatted_amount} has been waived. You do not need to pay.",
      notification_type: "match_payment_waived"
    )
  end

  def formatted_amount
    format("%.2f", @match_payment.amount_pence / 100.0)
  end
end
