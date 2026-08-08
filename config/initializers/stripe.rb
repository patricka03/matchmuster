# Stripe.api_key = Rails.application.credentials.dig(:stripe, :secret_key)
# require "stripe"

Stripe.api_key = ENV.fetch("STRIPE_SECRET_KEY")
