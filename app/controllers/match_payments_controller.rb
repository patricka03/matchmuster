class MatchPaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :set_match
  before_action :authorize_team_member!
  before_action :set_match_payment, only: %i[show update destroy checkout]
  before_action :authorize_manager!, only: %i[create bulk_create update destroy summary]
  before_action :authorize_payment_view!, only: %i[show]
  before_action :authorize_checkout!, only: %i[checkout]

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
    squad_selection = @match.squad_selections.find_by(
      user_id: create_payment_params[:user_id]
    )

    unless squad_selection
      return render json: {
        error: "Payment can only be requested from a player selected for this match"
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

  def bulk_create
    amount_pence = bulk_payment_params[:amount_pence]

    created_count = 0
    skipped_count = 0

    @match.squad_selections.includes(:user).each do |selection|
      match_payment = @match.match_payments.find_or_initialize_by(
        user: selection.user
      )

      if match_payment.persisted?
        skipped_count += 1
        next
      end

      match_payment.amount_pence = amount_pence

      if match_payment.save
        @match_payment = match_payment
        create_match_payment_notification
        created_count += 1
      end
    end

    render json: {
      message: "Bulk match-payment request completed",
      created_count: created_count,
      skipped_count: skipped_count
    }, status: :created
  end

  def update
    new_status = update_payment_params[:status]
    new_amount = update_payment_params[:amount_pence]

    amount_changed =
      new_amount.present? &&
      new_amount.to_i != @match_payment.amount_pence

    if new_amount.present? && @match_payment.status != "pending"
      return render json: {
        error: "Only pending payment amounts can be changed"
      }, status: :unprocessable_entity
    end

    if new_status.present? && !%w[pending paid waived].include?(new_status)
      return render json: {
        error: "Status must be pending, paid or waived"
      }, status: :unprocessable_entity
    end

    attributes = {}
    attributes[:amount_pence] = new_amount if new_amount.present?

    if new_status.present?
      attributes[:status] = new_status
      attributes[:paid_at] = new_status == "paid" ? Time.current : nil
    end

    if @match_payment.update(attributes)
      if @match_payment.saved_change_to_status?
        create_paid_notification if @match_payment.status == "paid"
        create_waived_notification if @match_payment.status == "waived"
      end

      create_amount_changed_notification if amount_changed

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

  def checkout
    if @match_payment.status != "pending"
      return render json: {
        error: "Only pending payments can be paid"
      }, status: :unprocessable_entity
    end

    if @team.stripe_account_id.blank?
      return render json: {
        error: "This team has not connected Stripe"
      }, status: :unprocessable_entity
    end

    stripe_account = Stripe::Account.retrieve(@team.stripe_account_id)

    unless stripe_account.charges_enabled
      return render json: {
        error: "This team's Stripe account is not ready to accept payments"
      }, status: :unprocessable_entity
    end

    checkout_session = Stripe::Checkout::Session.create(
      {
        mode: "payment",
        line_items: [
          {
            price_data: {
              currency: "gbp",
              unit_amount: @match_payment.amount_pence,
              product_data: {
                name: "Match payment"
              }
            },
            quantity: 1
          }
        ],
        success_url: "http://localhost:5173/payments/success?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: "http://localhost:5173/payments/cancelled",
        metadata: {
          match_payment_id: @match_payment.id
        },
        payment_intent_data: {
          metadata: {
            match_payment_id: @match_payment.id
          }
        }
      },
      {
        stripe_account: @team.stripe_account_id
      }
    )

    @match_payment.update!(
      stripe_checkout_session_id: checkout_session.id
    )

    render json: {
      checkout_url: checkout_session.url
    }, status: :ok
  rescue Stripe::StripeError => error
    render json: {
      error: error.message
    }, status: :unprocessable_entity
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

  def authorize_checkout!
    return if @match_payment.user_id == current_user.id

    render json: {
      error: "You can only pay your own match payment"
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

  def bulk_payment_params
    params.require(:match_payment).permit(:amount_pence)
  end

  def update_payment_params
    params.require(:match_payment).permit(:status, :amount_pence)
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

  def create_amount_changed_notification
    @match_payment.user.notifications.create!(
      title: "Match payment amount updated",
      message: "Your match payment amount has been changed to £#{formatted_amount}.",
      notification_type: "match_payment_amount_changed"
    )
  end

  def formatted_amount
    format("%.2f", @match_payment.amount_pence / 100.0)
  end
end
