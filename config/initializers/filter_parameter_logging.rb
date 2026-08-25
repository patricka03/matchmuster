# Be sure to restart your server if this file changes.

# Configure parameters to be partially matched (for example, `passw` matches
# `password`) and filtered from application logs.
Rails.application.config.filter_parameters += [
  :passw,
  :email,
  :secret,
  :token,
  :_key,
  :crypt,
  :salt,
  :certificate,
  :otp,
  :ssn,
  :cvv,
  :cvc,
  :signed_transaction,
  :signed_payload,
  :signedPayload
]
