module Developers
  class ManagersController < BaseController
    before_action :set_manager, only: %i[approve reject]

    def index
      managers = User.where(
        account_type: "manager",
        manager_verification_status: "pending"
      ).order(created_at: :asc)

      render json: {
        message: "Pending manager applications loaded successfully",
        count: managers.count,
        managers: managers.map { |manager| manager_json(manager) }
      }, status: :ok
    end

    def approve
      update_manager_status("approved")
    end

    def reject
      unless @manager.manager_verification_status == "pending"
        return render json: {
          error: "This manager application has already been #{@manager.manager_verification_status}"
        }, status: :conflict
      end

      deleted_manager = {
        id: @manager.id,
        email: @manager.email
      }

      begin
        UserMailer.manager_rejected_email(
          email: @manager.email,
          first_name: @manager.first_name
        ).deliver_now
      rescue StandardError => error
        Rails.logger.error(
          "Manager rejection email failed for user #{@manager.id}: #{error.message}"
        )

        return render json: {
          error: "The rejection email could not be sent. The account was not deleted."
        }, status: :unprocessable_entity
      end

      begin
        @manager.destroy!
      rescue ActiveRecord::RecordNotDestroyed,
            ActiveRecord::InvalidForeignKey,
            ActiveRecord::DeleteRestrictionError => error
        Rails.logger.error(
          "Rejected manager #{@manager.id} could not be deleted: #{error.message}"
        )

        return render json: {
          error: "The email was sent, but the account could not be deleted."
        }, status: :unprocessable_entity
      end

      render json: {
        message: "Manager rejected, rejection email sent, and account deleted successfully",
        deleted_manager: deleted_manager
      }, status: :ok
    end

    private

    def set_manager
      @manager = User.find_by(
        id: params[:id],
        account_type: "manager"
      )

      return if @manager

      render json: {
        error: "Manager not found"
      }, status: :not_found
    end

    def update_manager_status(new_status)
      unless @manager.manager_verification_status == "pending"
        return render json: {
          error: "This manager application has already been #{@manager.manager_verification_status}"
        }, status: :conflict
      end

      if @manager.update(manager_verification_status: new_status)
        render json: {
          message: "Manager application #{new_status} successfully",
          manager: manager_json(@manager)
        }, status: :ok
      else
        render json: {
          errors: @manager.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    def manager_json(manager)
      {
        id: manager.id,
        first_name: manager.first_name,
        last_name: manager.last_name,
        full_name: [
          manager.first_name,
          manager.last_name
        ].compact.join(" "),
        email: manager.email,
        status: manager.manager_verification_status,
        applied_at: manager.created_at,
        updated_at: manager.updated_at
      }
    end
  end
end
