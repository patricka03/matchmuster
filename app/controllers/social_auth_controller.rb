class SocialAuthController < ApplicationController
  TERMS_VERSION = "1.0".freeze
  PRIVACY_VERSION = "1.0".freeze
  AGE_DECLARATION_VERSION = "1.0".freeze

  def create
    verified =
      SocialIdentityVerifier.call(
        provider: social_auth_params[:provider],
        id_token: social_auth_params[:id_token]
      )

    identity =
      SocialIdentity.find_by(
        provider: verified[:provider],
        uid: verified[:uid]
      )

    user = identity&.user
    created = false

    unless user
      user = find_user_by_verified_email(verified[:email])

      unless user
        user = create_social_user!(verified)
        created = true
      end

      user.social_identities.create!(
        provider: verified[:provider],
        uid: verified[:uid],
        email: verified[:email]
      )
    end

    if user.access_restricted?
      return render json: {
        error: "This MatchMuster account is not available."
      }, status: :unauthorized
    end

    token, =
      Warden::JWTAuth::UserEncoder
        .new
        .call(
          user,
          :user,
          nil
        )

    response.set_header(
      "Authorization",
      "Bearer #{token}"
    )

    render json: {
      message:
        created ?
          "Account created successfully." :
          "Signed in successfully.",
      created: created,
      user: user_json(user)
    }, status:
      created ?
        :created :
        :ok
  rescue SocialIdentityVerifier::VerificationError => error
    render json: {
      error: error.message
    }, status: :unauthorized
  rescue ActiveRecord::RecordInvalid => error
    render json: {
      errors: error.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  private

  def social_auth_params
    params.permit(
      :provider,
      :id_token,
      :account_type,
      :first_name,
      :last_name,
      :age_confirmed,
      :terms_accepted
    )
  end

  def find_user_by_verified_email(email)
    return nil if email.blank?

    User.find_by(
      "LOWER(email) = ?",
      email.downcase
    )
  end

  def create_social_user!(verified)
    account_type =
      social_auth_params[:account_type]
        .to_s
        .strip

    unless %w[manager player].include?(account_type)
      raise validation_error("Choose Manager or Player.")
    end

    unless boolean_param(:age_confirmed)
      raise validation_error(
        "You must confirm that you are 18 years of age or older."
      )
    end

    unless boolean_param(:terms_accepted)
      raise validation_error(
        "You must agree to the Terms of Service."
      )
    end

    email = verified[:email]

    if email.blank?
      raise validation_error(
        "Your provider did not share an email address. Please allow email access and try again."
      )
    end

    first_name = social_auth_params[:first_name].to_s.strip
    last_name = social_auth_params[:last_name].to_s.strip

    if first_name.blank? || last_name.blank?
      raise validation_error(
        "Enter your first and last name, then try social sign-up again."
      )
    end

    password = SecureRandom.base64(48)

    user =
      User.new(
        first_name: first_name,
        last_name: last_name,
        email: email,
        account_type: account_type,
        password: password,
        password_confirmation: password
      )

    User.transaction do
      user.save!
      create_legal_acceptances!(user)
    end

    UserMailer.welcome_email(user).deliver_later
    user
  end

  def validation_error(message)
    user = User.new
    user.errors.add(:base, message)
    ActiveRecord::RecordInvalid.new(user)
  end

  def boolean_param(key)
    ActiveModel::Type::Boolean
      .new
      .cast(
        social_auth_params[key]
      )
  end

  def create_legal_acceptances!(user)
    [
      ["terms", TERMS_VERSION],
      ["privacy_notice", PRIVACY_VERSION],
      ["age_declaration", AGE_DECLARATION_VERSION]
    ].each do |document_type, document_version|
      user.legal_acceptances.create!(
        document_type: document_type,
        document_version: document_version,
        accepted_at: Time.current
      )
    end
  end

  def user_json(user)
    {
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      account_type: user.account_type,
      manager_verification_status:
        user.manager_verification_status
    }
  end
end
