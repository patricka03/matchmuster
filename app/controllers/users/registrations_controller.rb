module Users
  class RegistrationsController < Devise::RegistrationsController
    respond_to :json

    def create
      build_resource(sign_up_params)

      if resource.save
        UserMailer.welcome_email(resource).deliver_later
        render json: {
          message: "Account created successfully.",
          user: {
            id: resource.id,
            first_name: resource.first_name,
            last_name: resource.last_name,
            email: resource.email,
            account_type: resource.account_type,
            manager_verification_status: resource.manager_verification_status
          }
        }, status: :created
      else
        clean_up_passwords(resource)

        render json: {
          errors: resource.errors.full_messages
        }, status: :unprocessable_entity
      end
    end
  end
end
