module Users
  class RegistrationsController < Devise::RegistrationsController
    respond_to :json

    TERMS_VERSION = "1.0".freeze
    PRIVACY_VERSION = "1.0".freeze
    AGE_DECLARATION_VERSION = "1.0".freeze

    def create
      unless age_confirmed?
        return render json: {
          errors: [
            "You must confirm that you are 18 years of age or older."
          ]
        }, status: :unprocessable_entity
      end

      unless terms_accepted?
        return render json: {
          errors: [
            "You must agree to the Terms of Service."
          ]
        }, status: :unprocessable_entity
      end

      build_resource(sign_up_params)

      begin
        User.transaction do
          resource.save!

          resource.legal_acceptances.create!(
            document_type: "terms",
            document_version: TERMS_VERSION,
            accepted_at: Time.current
          )

          resource.legal_acceptances.create!(
            document_type: "privacy_notice",
            document_version: PRIVACY_VERSION,
            accepted_at: Time.current
          )

          resource.legal_acceptances.create!(
            document_type: "age_declaration",
            document_version: AGE_DECLARATION_VERSION,
            accepted_at: Time.current
          )
        end

        UserMailer.welcome_email(resource).deliver_later

        render json: {
          message: "Account created successfully.",
          user: {
            id: resource.id,
            first_name: resource.first_name,
            last_name: resource.last_name,
            email: resource.email,
            account_type: resource.account_type,
            manager_verification_status:
              resource.manager_verification_status
          }
        }, status: :created

      rescue ActiveRecord::RecordInvalid => error
        clean_up_passwords(resource)

        errors =
          if resource.errors.any?
            resource.errors.full_messages
          else
            error.record.errors.full_messages
          end

        render json: {
          errors: errors
        }, status: :unprocessable_entity
      end
    end

    private

    def age_confirmed?
      ActiveModel::Type::Boolean.new.cast(
        params[:age_confirmed]
      )
    end

    def terms_accepted?
      ActiveModel::Type::Boolean.new.cast(
        params[:terms_accepted]
      )
    end
  end
end
