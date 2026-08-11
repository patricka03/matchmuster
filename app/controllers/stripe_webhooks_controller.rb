class StripeWebhooksController < ApplicationController
  def create
    payload = request.raw_post
    signature = request.headers["Stripe-Signature"]

    webhook_secret =
      ENV["STRIPE_WEBHOOK_SECRET"].presence ||
      Rails.application.credentials.dig(
        :stripe,
        :webhook_secret
      )

    if webhook_secret.blank?
      Rails.logger.error(
        "[Stripe webhook] STRIPE_WEBHOOK_SECRET is missing"
      )

      return render json: {
        error: "Webhook is not configured"
      }, status: :internal_server_error
    end

    event = Stripe::Webhook.construct_event(
      payload,
      signature,
      webhook_secret
    )

    case event.type
    when "checkout.session.completed",
         "checkout.session.async_payment_succeeded"
      handle_successful_checkout(event)
    end

    head :ok
  rescue JSON::ParserError
    render json: {
      error: "Invalid webhook payload"
    }, status: :bad_request
  rescue Stripe::SignatureVerificationError
    render json: {
      error: "Invalid webhook signature"
    }, status: :bad_request
  end

  private

  def handle_successful_checkout(event)
    checkout_session = event.data.object

    unless checkout_session.payment_status == "paid"
      return ignore_event(
        event,
        "Checkout Session is not paid"
      )
    end

    unless checkout_session.mode == "payment"
      return ignore_event(
        event,
        "Checkout Session mode is not payment"
      )
    end

    match_payment_id =
      checkout_session.metadata&.[]("match_payment_id")

    if match_payment_id.blank?
      return ignore_event(
        event,
        "match_payment_id metadata is missing"
      )
    end

    match_payment = MatchPayment.find_by(
      id: match_payment_id
    )

    unless match_payment
      return ignore_event(
        event,
        "MatchPayment #{match_payment_id} was not found"
      )
    end

    match_payment.with_lock do
      return if match_payment.status == "paid"

      expected_account_id =
        match_payment.match.team.stripe_account_id

      unless expected_account_id.present? &&
          event.account == expected_account_id
        return ignore_event(
          event,
          "Connected Stripe account does not match"
        )
      end

      unless checkout_session.id ==
          match_payment.stripe_checkout_session_id
        return ignore_event(
          event,
          "Checkout Session ID does not match"
        )
      end

      unless checkout_session.amount_total ==
          match_payment.amount_pence
        return ignore_event(
          event,
          "Checkout amount does not match"
        )
      end

      unless checkout_session.currency.to_s.downcase == "gbp"
        return ignore_event(
          event,
          "Checkout currency is not GBP"
        )
      end

      payment_intent = checkout_session.payment_intent

      payment_intent_id =
        if payment_intent.respond_to?(:id)
          payment_intent.id
        else
          payment_intent
        end

      if payment_intent_id.blank?
        return ignore_event(
          event,
          "PaymentIntent ID is missing"
        )
      end

      match_payment.update!(
        status: "paid",
        paid_at: Time.at(event.created).utc,
        stripe_checkout_session_id: checkout_session.id,
        stripe_payment_intent_id: payment_intent_id
      )

      match_payment.user.notifications.create!(
        title: "Match payment received",
        message: payment_received_message(match_payment),
        notification_type: "match_payment_paid",
        match_payment_id: match_payment.id,
        match_id: match_payment.match_id
      )
    end
  end

  def payment_received_message(match_payment)
    amount = format(
      "%.2f",
      match_payment.amount_pence / 100.0
    )

    "Your payment of £#{amount} has been received."
  end

  def ignore_event(event, reason)
    Rails.logger.warn(
      "[Stripe webhook] Ignored event #{event.id}: #{reason}"
    )

    nil
  end
end
