module Developers
  class UsersController < BaseController
    VALID_STATUSES = %w[
      active
      suspended
      banned
      deleted
    ].freeze

    VALID_ACCOUNT_TYPES = %w[
      player
      manager
    ].freeze

    before_action :set_user,
                  only: %i[
                    suspend
                    ban
                    restore
                    destroy
                  ]

    rescue_from DeveloperAccountService::Error,
                with: :render_account_error

    def index
      users =
        User
          .includes(
            :teams,
            :legal_acceptances
          )

      users =
        filter_by_query(
          users
        )

      users =
        filter_by_status(
          users
        )

      users =
        filter_by_account_type(
          users
        )

      render json: {
        users:
          users
            .order(
              created_at: :desc
            )
            .limit(200)
            .map do |user|
              user_json(user)
            end,

        summary:
          account_summary
      }, status: :ok
    end

    def suspend
      account_service
        .suspend!

      render_user(
        "Account suspended successfully."
      )
    end

    def ban
      account_service
        .ban!

      render_user(
        "Account banned successfully."
      )
    end

    def restore
      account_service
        .restore!

      render_user(
        "Account reactivated successfully."
      )
    end

    def destroy
      account_service
        .delete!(
          confirmation:
            account_params[
              :confirmation
            ]
        )

      render_user(
        "Account deleted and anonymised successfully."
      )
    end

    private

    def set_user
      @user =
        User.find(
          params[:id]
        )
    end

    def account_service
      DeveloperAccountService.new(
        user: @user,
        developer: current_developer,
        notes:
          account_params[
            :notes
          ]
      )
    end

    def account_params
      params
        .require(:user)
        .permit(
          :notes,
          :confirmation
        )
    end

    def filter_by_query(users)
      query =
        params[
          :query
        ]
          .to_s
          .strip
          .downcase

      return users if query.blank?

      escaped_query =
        ActiveRecord::Base
          .sanitize_sql_like(
            query
          )

      pattern =
        "%#{escaped_query}%"

      users.where(
        "LOWER(first_name) LIKE :query OR LOWER(last_name) LIKE :query OR LOWER(email) LIKE :query",
        query: pattern
      )
    end

    def filter_by_status(users)
      status =
        params[
          :status
        ]
          .to_s

      return users if status.blank?

      unless VALID_STATUSES.include?(status)
        raise DeveloperAccountService::Error,
              "Invalid account status."
      end

      case status
      when "active"
        users.where(
          deleted_at: nil,
          suspended_at: nil,
          banned_at: nil
        )

      when "suspended"
        users
          .where(
            deleted_at: nil,
            banned_at: nil
          )
          .where.not(
            suspended_at: nil
          )

      when "banned"
        users
          .where(
            deleted_at: nil
          )
          .where.not(
            banned_at: nil
          )

      when "deleted"
        users.where.not(
          deleted_at: nil
        )
      end
    end

    def filter_by_account_type(users)
      account_type =
        params[
          :account_type
        ]
          .to_s

      return users if account_type.blank?

      unless VALID_ACCOUNT_TYPES.include?(account_type)
        raise DeveloperAccountService::Error,
              "Invalid account type."
      end

      users.where(
        account_type:
          account_type
      )
    end

    def account_summary
      {
        active:
          User.where(
            deleted_at: nil,
            suspended_at: nil,
            banned_at: nil
          ).count,

        suspended:
          User
            .where(
              deleted_at: nil,
              banned_at: nil
            )
            .where.not(
              suspended_at: nil
            )
            .count,

        banned:
          User
            .where(
              deleted_at: nil
            )
            .where.not(
              banned_at: nil
            )
            .count,

        deleted:
          User
            .where.not(
              deleted_at: nil
            )
            .count
      }
    end

    def render_user(message)
      @user.reload

      render json: {
        message: message,
        user:
          user_json(
            @user
          )
      }, status: :ok
    end

    def user_json(user)
      {
        id: user.id,
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email,
        account_type: user.account_type,
        manager_verification_status:
          user.manager_verification_status,
        status:
          account_status(user),
        restriction_reason:
          user.suspension_reason,
        suspended_at: user.suspended_at,
        banned_at: user.banned_at,
        deleted_at: user.deleted_at,
        created_at: user.created_at,
        team_names:
          user
            .teams
            .map(&:name)
            .uniq
            .sort,
        legal_acceptance_count:
          user
            .legal_acceptances
            .size
      }
    end

    def account_status(user)
      return "deleted" if user.deleted?
      return "banned" if user.banned?
      return "suspended" if user.suspended?

      "active"
    end

    def render_account_error(error)
      render json: {
        error: error.message
      }, status: :unprocessable_entity
    end
  end
end
