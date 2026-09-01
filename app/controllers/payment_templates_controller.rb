class PaymentTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :authorize_manager!
  before_action :require_templates_plus!
  before_action :set_template, only: %i[update destroy]
  before_action :require_recurring_plus!, only: %i[create update]

  def index
    templates = @team.payment_templates.order(:name)

    render json: {
      templates: templates.map { |template| template_json(template) }
    }, status: :ok
  end

  def create
    template = @team.payment_templates.new(template_params)
    template.created_by = current_user

    if template.save
      render json: { template: template_json(template) }, status: :created
    else
      render json: { errors: template.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  def update
    if @template.update(template_params)
      render json: { template: template_json(@template) }, status: :ok
    else
      render json: { errors: @template.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy!
    head :no_content
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_template
    @template = @team.payment_templates.find(params[:id])
  end

  def authorize_manager!
    membership = current_user.team_memberships.find_by(
      team_id: @team.id,
      role: "manager",
      status: "approved"
    )

    return if current_user.account_type == "manager" &&
              current_user.manager_verification_status == "approved" &&
              membership

    render json: { error: "Only an approved team manager can manage payment templates." },
           status: :forbidden
  end

  def require_templates_plus!
    require_plus!(team: @team, feature: :saved_payment_templates)
  end

  def require_recurring_plus!
    recurrence = params.dig(:payment_template, :recurrence)
    return unless recurrence == "monthly"

    require_plus!(team: @team, feature: :recurring_payments)
  end

  def template_params
    params.require(:payment_template).permit(
      :name,
      :payment_type,
      :title,
      :description,
      :amount_pence,
      :default_due_days,
      :recurrence,
      :next_run_on,
      :active
    )
  end

  def template_json(template)
    template.as_json(
      only: %i[
        id name payment_type title description amount_pence default_due_days
        recurrence next_run_on active created_at updated_at
      ]
    )
  end
end
