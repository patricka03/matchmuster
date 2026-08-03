class StripeWebhooksController < ApplicationController
  def create
    payload = request.raw_post
    signature = request.headers["Stripe-Signature"]
    webhook_secret =
      Rails.application.credentials.dig(:stripe, :webhook_secret)

    event = Stripe::Webhook.construct_event(
      payload,
      signature,
      webhook_secret
    )

    handle_checkout_completed(event) if event.type == "checkout.session.completed"

    head :ok
  rescue JSON::ParserError, Stripe::SignatureVerificationError
    render json: {
      error: "Invalid webhook signature"
    }, status: :bad_request
  end

  private

  def handle_checkout_completed(event)
    checkout_session = event.data.object

    return unless checkout_session.payment_status == "paid"

    match_payment_id = checkout_session.metadata.match_payment_id
    match_payment = MatchPayment.find_by(id: match_payment_id)

    return unless match_payment

    connected_account_id = event.account
    team_account_id = match_payment.match.team.stripe_account_id

    return unless connected_account_id == team_account_id

    match_payment.with_lock do
      return if match_payment.status == "paid"

      match_payment.update!(
        status: "paid",
        paid_at: Time.current,
        stripe_payment_intent_id: checkout_session.payment_intent
      )

      match_payment.user.notifications.create!(
        title: "Match payment received",
        message: "Your payment of £#{format('%.2f', match_payment.amount_pence / 100.0)} has been received.",
        notification_type: "match_payment_paid"
      )
    end
  end
end
