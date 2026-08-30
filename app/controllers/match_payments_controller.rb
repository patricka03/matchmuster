class MatchPaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :set_match
  before_action :authorize_team_member!
  before_action :set_match_payment, only: %i[show update destroy checkout]
  before_action :authorize_manager!, only: %i[create bulk_create update destroy summary]
  before_action :require_payment_analytics_plus!, only: %i[ summary ]
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

    @match_payment = @match.match_payments.new(
      create_payment_params
    )

    if @match_payment.save
      create_match_payment_notification

      render json: @match_payment,
             status: :created
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
    requested_status =
      update_payment_params[:status].presence

    new_amount =
      update_payment_params[:amount_pence]

    allowed_statuses =
      %w[
        paid
        waived
        pending
      ]

    if requested_status.present? &&
        !allowed_statuses.include?(requested_status)
      return render json: {
        error:
          "Managers can mark a Match Sub as paid in cash, waive it, or reset it to pending."
      }, status: :unprocessable_entity
    end

    parsed_amount =
      Integer(
        new_amount,
        exception: false
      ) if new_amount.present?

    if new_amount.present? &&
        parsed_amount.nil?
      return render json: {
        error:
          "Amount must be a whole number of pence"
      }, status: :unprocessable_entity
    end

    @match_payment.with_lock do
      amount_changed =
        parsed_amount.present? &&
        parsed_amount !=
          @match_payment.amount_pence

      status_changed =
        requested_status.present? &&
        requested_status !=
          @match_payment.status

      unless amount_changed ||
          status_changed
        return render json:
          @match_payment,
          status: :ok
      end

      if amount_changed &&
          @match_payment.status !=
            "pending"
        return render json: {
          error:
            "Only pending payments can have their amount changed"
        }, status: :unprocessable_entity
      end

      case requested_status
      when "paid"
        unless @match_payment.status ==
            "pending"
          return render json: {
            error:
              "Only a pending Match Sub can be marked as paid in cash"
          }, status: :unprocessable_entity
        end

      when "waived"
        unless @match_payment.status ==
            "pending"
          return render json: {
            error:
              "Only a pending Match Sub can be waived"
          }, status: :unprocessable_entity
        end

      when "pending"
        unless %w[
          paid
          waived
        ].include?(
          @match_payment.status
        )
          return render json: {
            error:
              "Only paid or waived Match Subs can be reset to pending"
          }, status: :unprocessable_entity
        end

        if @match_payment.status ==
            "paid" &&
            @match_payment
              .stripe_payment_intent_id
              .present?
          return render json: {
            error:
              "Stripe-confirmed payments cannot be reset to pending"
          }, status: :unprocessable_entity
        end
      end

      needs_checkout_clear =
        amount_changed ||
        %w[
          paid
          waived
        ].include?(
          requested_status
        )

      if needs_checkout_clear
        session_state =
          expire_stored_checkout_session

        unless session_state ==
            :cleared
          return render json: {
            error:
              "Stripe is confirming this payment. Please refresh shortly."
          }, status: :conflict
        end
      end

      attributes = {}

      if amount_changed
        attributes[:amount_pence] =
          parsed_amount
      end

      case requested_status
      when "paid"
        attributes[:status] =
          "paid"

        attributes[:paid_at] =
          Time.current

        attributes[
          :stripe_checkout_session_id
        ] = nil

      when "waived"
        attributes[:status] =
          "waived"

        attributes[:paid_at] =
          nil

        attributes[
          :stripe_checkout_session_id
        ] = nil

      when "pending"
        attributes[:status] =
          "pending"

        attributes[:paid_at] =
          nil

        # A manually-paid or waived Match Sub
        # must reopen cleanly.
        attributes[
          :stripe_checkout_session_id
        ] = nil
      end

      if @match_payment.update(
        attributes
      )
        if requested_status ==
            "paid"
          create_cash_paid_notification

        elsif requested_status ==
            "waived"
          create_waived_notification

        elsif amount_changed
          create_amount_changed_notification
        end

        render json:
          @match_payment,
          status: :ok
      else
        render json: {
          errors:
            @match_payment
              .errors
              .full_messages
        }, status: :unprocessable_entity
      end
    end
  rescue Stripe::StripeError => error
    Rails.logger.error(
      "[Stripe Checkout cancellation] #{error.message}"
    )

    render json: {
      error:
        "Stripe could not safely cancel the Checkout Session. No changes were made."
    }, status: :unprocessable_entity
  end

  def destroy
    unless @match_payment.status == "pending"
      return render json: {
        error: "Only pending payment requests can be deleted"
      }, status: :unprocessable_entity
    end

    @match_payment.destroy!

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
    if @team.stripe_account_id.blank?
      return render json: {
        error: "This team has not connected Stripe"
      }, status: :unprocessable_entity
    end

    stripe_account = Stripe::Account.retrieve(
      @team.stripe_account_id
    )

    unless stripe_account.charges_enabled
      return render json: {
        error: "This team's Stripe account is not ready to accept payments"
      }, status: :unprocessable_entity
    end

    frontend_url = ENV.fetch(
      "FRONTEND_URL",
      "http://localhost:5173"
    ).delete_suffix("/")

    checkout_session = nil
    payment_not_pending = false
    payment_being_confirmed = false

    @match_payment.with_lock do
      if @match_payment.status != "pending"
        payment_not_pending = true
        next
      end

      if @match_payment.stripe_checkout_session_id.present?
        existing_session = Stripe::Checkout::Session.retrieve(
          @match_payment.stripe_checkout_session_id,
          {
            stripe_account: @team.stripe_account_id
          }
        )

        if existing_session.status == "open" &&
            existing_session.url.present?
          checkout_session = existing_session
          next
        end

        if existing_session.status == "complete"
          payment_being_confirmed = true
          next
        end
      end

      idempotency_key = [
        "match-payment-checkout",
        @match_payment.id,
        @match_payment.amount_pence,
        @match_payment.updated_at.to_i,
        @match_payment.updated_at.usec
      ].join("-")

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
          success_url: "#{frontend_url}/dashboard?payment=success",
          cancel_url: "#{frontend_url}/payments/cancelled",
          metadata: {
            match_payment_id: @match_payment.id.to_s
          },
          payment_intent_data: {
            metadata: {
              match_payment_id: @match_payment.id.to_s
            }
          }
        },
        {
          stripe_account: @team.stripe_account_id,
          idempotency_key: idempotency_key
        }
      )

      @match_payment.update!(
        stripe_checkout_session_id: checkout_session.id
      )
    end

    if payment_not_pending
      return render json: {
        error: "Only pending payments can be paid"
      }, status: :unprocessable_entity
    end

    if payment_being_confirmed
      return render json: {
        error: "Stripe is confirming this payment. Please refresh shortly."
      }, status: :accepted
    end

    render json: {
      checkout_url: checkout_session.url,
      checkout_session_id: checkout_session.id
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

  def require_payment_analytics_plus!
    require_plus!(
      team: @team,
      feature:
        :payment_analytics
    )
  end

  def bulk_payment_params
    params.require(:match_payment).permit(:amount_pence)
  end

  def update_payment_params
    params.require(:match_payment).permit(:status, :amount_pence)
  end

  def create_match_payment_notification
    NotificationEvents.payment_requested(
      match_payment: @match_payment,
      actor: current_user
    )
  end

  def create_cash_paid_notification
    NotificationEvents.payment_marked_paid_manually(
      match_payment: @match_payment,
      actor: current_user
    )
  end

  def create_waived_notification
    NotificationEvents.payment_waived(
      match_payment: @match_payment,
      actor: current_user
    )
  end

  def create_amount_changed_notification
    NotificationEvents.payment_updated(
      match_payment: @match_payment,
      actor: current_user
    )
  end

  def expire_stored_checkout_session
    return :cleared if @match_payment.stripe_checkout_session_id.blank?

    checkout_session = Stripe::Checkout::Session.retrieve(
      @match_payment.stripe_checkout_session_id,
      {
        stripe_account: @team.stripe_account_id
      }
    )

    case checkout_session.status
    when "open"
      Stripe::Checkout::Session.expire(
        checkout_session.id,
        {},
        {
          stripe_account: @team.stripe_account_id
        }
      )

      :cleared
    when "expired"
      :cleared
    else
      :payment_processing
    end
  end
end
