class TeamFinanceEntriesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :authorize_manager!
  before_action :require_club_finance_plus!
  before_action :set_entry,
                only: %i[update destroy]

  def create
    entry =
      @team.team_finance_entries.new(entry_params)

    entry.created_by = current_user

    if entry.save
      render json: {
        entry: entry_json(entry)
      }, status: :created
    else
      render json: {
        errors: entry.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    if @entry.update(entry_params)
      render json: {
        entry: entry_json(@entry)
      }, status: :ok
    else
      render json: {
        errors: @entry.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    @entry.destroy!
    head :no_content
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_entry
    @entry =
      @team.team_finance_entries.find(params[:id])
  end

  def authorize_manager!
    membership =
      current_user.team_memberships.find_by(
        team_id: @team.id,
        role: "manager",
        status: "approved"
      )

    return if current_user.account_type == "manager" &&
              current_user.manager_verification_status == "approved" &&
              membership

    render json: {
      error: "Only an approved team manager can manage club finances."
    }, status: :forbidden
  end

  def require_club_finance_plus!
    require_plus!(
      team: @team,
      feature: :club_finance
    )
  end

  def entry_params
    params
      .require(:team_finance_entry)
      .permit(
        :entry_type,
        :category,
        :description,
        :amount_pence,
        :occurred_on
      )
  end

  def entry_json(entry)
    {
      id: entry.id,
      entry_type: entry.entry_type,
      category: entry.category,
      description: entry.description,
      amount_pence: entry.amount_pence,
      occurred_on: entry.occurred_on,
      match_id: entry.match_id,
      created_at: entry.created_at,
      updated_at: entry.updated_at
    }
  end
end
