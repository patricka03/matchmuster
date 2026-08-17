module Developers
  class ReportsController < BaseController
    before_action :set_report,
                  only: %i[
                    show
                    update
                    remove_content
                    suspend_user
                    ban_user
                    restore_user
                    delete_user
                  ]

    rescue_from ModerationService::Error,
                with: :render_moderation_error

    def index
      reports =
        Report
          .includes(
            :reporter,
            :reported_user,
            :reviewed_by,
            :reportable,
            :moderation_actions
          )
          .newest_first

      if params[:status].present?
        unless Report::STATUSES.include?(
          params[:status]
        )
          return render json: {
            error: "Invalid report status."
          }, status: :unprocessable_entity
        end

        reports =
          reports.where(
            status:
              params[:status]
          )
      end

      render json: {
        reports:
          reports
            .limit(200)
            .map do |report|
              report_json(report)
            end
      }, status: :ok
    end

    def show
      render_report
    end

    def update
      service =
        moderation_service

      case moderation_params[:status]
      when "reviewing"
        service.start_review!(
          notes:
            moderation_params[
              :moderation_notes
            ]
        )

      when "dismissed"
        service.dismiss!(
          notes:
            moderation_params[
              :moderation_notes
            ]
        )

      else
        return render json: {
          error:
            "Status must be reviewing or dismissed."
        }, status: :unprocessable_entity
      end

      render_report
    end

    def remove_content
      moderation_service
        .remove_content!(
          notes:
            moderation_params[
              :moderation_notes
            ]
        )

      render_report
    end

    def suspend_user
      moderation_service
        .suspend_user!(
          notes:
            moderation_params[
              :moderation_notes
            ]
        )

      render_report
    end

    def ban_user
      moderation_service
        .ban_user!(
          notes:
            moderation_params[
              :moderation_notes
            ]
        )

      render_report
    end

    def restore_user
      moderation_service
        .restore_user!(
          notes:
            moderation_params[
              :moderation_notes
            ]
        )

      render_report
    end

    def delete_user
      moderation_service
        .delete_user!(
          notes:
            moderation_params[
              :moderation_notes
            ]
        )

      render_report
    end

    private

    def set_report
      @report =
        Report.find(
          params[:id]
        )
    end

    def moderation_service
      ModerationService.new(
        report:
          @report,

        developer:
          current_developer
      )
    end

    def moderation_params
      params
        .require(:report)
        .permit(
          :status,
          :moderation_notes
        )
    end

    def render_report
      @report.reload

      render json: {
        report:
          report_json(
            @report
          )
      }, status: :ok
    end

    def report_json(report)
      {
        id: report.id,
        reason: report.reason,
        details: report.details,
        status: report.status,
        moderation_notes: report.moderation_notes,
        created_at: report.created_at,
        reviewed_at: report.reviewed_at,

        reporter:
          user_json(
            report.reporter
          ),

        reported_user:
          user_json(
            report.reported_user
          ),

        reviewed_by:
          developer_json(
            report.reviewed_by
          ),

        reportable:
          reportable_json(
            report.reportable
          ),

        moderation_actions:
          report
            .moderation_actions
            .order(
              created_at: :asc
            )
            .map do |action|
              moderation_action_json(
                action
              )
            end
      }
    end

    def user_json(user)
      return nil unless user

      {
        id: user.id,
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email,
        account_type: user.account_type,
        suspended: user.suspended?,
        banned: user.banned?,
        deleted: user.deleted?
      }
    end

    def developer_json(developer)
      return nil unless developer

      {
        id: developer.id,
        email: developer.email
      }
    end

    def reportable_json(reportable)
      case reportable
      when Post
        {
          type: "Post",
          id: reportable.id,
          team_id: reportable.team_id,
          title: reportable.title,
          content: reportable.content,
          post_type: reportable.post_type
        }

      when MatchRating
        {
          type: "MatchRating",
          id: reportable.id,
          match_id: reportable.match_id,
          rater_id: reportable.rater_id,
          player_id: reportable.player_id,
          rating: reportable.rating,
          comment: reportable.comment
        }

      else
        nil
      end
    end

    def moderation_action_json(action)
      {
        id: action.id,
        action_type: action.action_type,
        notes: action.notes,
        metadata: action.metadata,
        created_at: action.created_at,
        developer_id: action.developer_id,
        target_user_id: action.target_user_id
      }
    end

    def render_moderation_error(error)
      render json: {
        error: error.message
      }, status: :unprocessable_entity
    end
  end
end
