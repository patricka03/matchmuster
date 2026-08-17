class ReportsController < ApplicationController
  REPORTABLE_CLASSES = {
    "Post" => Post,
    "MatchRating" => MatchRating
  }.freeze

  before_action :authenticate_user!
  before_action :load_report_target
  before_action :authorize_report_target!

  def create
    existing_report =
      current_user
        .submitted_reports
        .unresolved
        .find_by(
          reportable: @reportable,
          reported_user: @reported_user
        )

    if existing_report
      return render json: {
        message: "You have already reported this item.",
        report: report_json(existing_report)
      }, status: :ok
    end

    reports_today =
      current_user
        .submitted_reports
        .where(
          "created_at >= ?",
          24.hours.ago
        )
        .count

    if reports_today >= 10
      return render json: {
        error: "You have reached the daily reporting limit."
      }, status: :too_many_requests
    end

    report =
      current_user
        .submitted_reports
        .new(
          reason:
            report_params[:reason],

          details:
            report_params[:details],

          reported_user:
            @reported_user,

          reportable:
            @reportable
        )

    if report.save
      render json: {
        message: "Your report has been submitted for review.",
        report: report_json(report)
      }, status: :created
    else
      render json: {
        errors:
          report
            .errors
            .full_messages
      }, status: :unprocessable_entity
    end
  end

  private

  def load_report_target
    reportable_type =
      report_params[:reportable_type]
        .to_s
        .strip

    reportable_id =
      report_params[:reportable_id]

    if reportable_type.present? ||
       reportable_id.present?
      return load_reportable(
        reportable_type,
        reportable_id
      )
    end

    reported_user_id =
      report_params[:reported_user_id]

    if reported_user_id.blank?
      return render json: {
        error: "A user or piece of content must be reported."
      }, status: :unprocessable_entity
    end

    @reported_user =
      User.find(
        reported_user_id
      )

    @reportable = nil
  end

  def load_reportable(
    reportable_type,
    reportable_id
  )
    reportable_class =
      REPORTABLE_CLASSES[
        reportable_type
      ]

    unless reportable_class &&
           reportable_id.present?
      return render json: {
        error: "That content cannot be reported."
      }, status: :unprocessable_entity
    end

    @reportable =
      reportable_class.find(
        reportable_id
      )

    @reported_user =
      case @reportable
      when Post
        @reportable.user
      when MatchRating
        @reportable.rater
      end
  end

  def authorize_report_target!
    authorised =
      if @reportable
        approved_member_of_team?(
          reportable_team_id
        )
      else
        shares_approved_team_with?(
          @reported_user
        )
      end

    return if authorised

    render json: {
      error: "You are not authorised to report this item."
    }, status: :forbidden
  end

  def reportable_team_id
    case @reportable
    when Post
      @reportable.team_id
    when MatchRating
      @reportable.match.team_id
    end
  end

  def approved_member_of_team?(
    team_id
  )
    current_user
      .team_memberships
      .exists?(
        team_id: team_id,
        status: "approved"
      )
  end

  def shares_approved_team_with?(
    user
  )
    current_team_ids =
      current_user
        .team_memberships
        .where(
          status: "approved"
        )
        .select(
          :team_id
        )

    user
      .team_memberships
      .where(
        status: "approved",
        team_id: current_team_ids
      )
      .exists?
  end

  def report_params
    params
      .require(:report)
      .permit(
        :reason,
        :details,
        :reported_user_id,
        :reportable_type,
        :reportable_id
      )
  end

  def report_json(report)
    {
      id: report.id,
      reason: report.reason,
      status: report.status,
      created_at: report.created_at
    }
  end
end
