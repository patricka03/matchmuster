class DisciplinaryRecordsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :authorize_team_member!
  before_action :set_record, only: %i[update destroy]
  before_action :authorize_manager!, only: %i[create update destroy]
  before_action :require_team_payments_plus!, only: %i[create update destroy]

  def index
    records = if approved_manager?
                @team.disciplinary_records
              else
                @team.disciplinary_records.where(player: current_user)
              end

    render json: {
      disciplinary_records:
        records.includes(:player, :match, :match_payment)
               .order(created_at: :desc)
               .limit(300)
               .map { |record| record_json(record) }
    }, status: :ok
  end

  def create
    attributes = record_params
    match = @team.matches.find(attributes[:match_id])
    player = approved_players.find(attributes[:player_id])
    payment = nil
    record = nil

    DisciplinaryRecord.transaction do
      if attributes[:fine_amount_pence].present? &&
         attributes[:fine_amount_pence].to_i.positive?
        payment = @team.match_payments.create!(
          user: player,
          match: match,
          requested_by: current_user,
          payment_type: payment_type_for(attributes[:card_type]),
          title: attributes[:fine_title],
          description: attributes[:reason],
          amount_pence: attributes[:fine_amount_pence],
          due_at: attributes[:fine_due_at]
        )
      end

      record = @team.disciplinary_records.create!(
        match: match,
        player: player,
        recorded_by: current_user,
        match_payment: payment,
        card_type: attributes[:card_type],
        incident_minute: attributes[:incident_minute],
        reason: attributes[:reason],
        notes: attributes[:notes],
        evidence_url: attributes[:evidence_url],
        suspension_matches: attributes[:suspension_matches].presence || 0,
        suspension_matches_remaining:
          attributes[:suspension_matches].presence || 0,
        appeal_status: attributes[:appeal_status].presence || "not_applicable"
      )

    end

    if payment
      NotificationEvents.payment_requested(
        match_payment: payment,
        actor: current_user
      )
    end

    NotificationEvents.disciplinary_recorded(
      disciplinary_record: record,
      actor: current_user
    )

    render json: { disciplinary_record: record_json(record.reload) },
           status: :created
  rescue ActiveRecord::RecordInvalid => error
    render json: { errors: error.record.errors.full_messages },
           status: :unprocessable_entity
  end

  def update
    if @record.update(update_params)
      render json: { disciplinary_record: record_json(@record) }, status: :ok
    else
      render json: { errors: @record.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  def destroy
    @record.destroy!
    head :no_content
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_record
    @record = @team.disciplinary_records.find(params[:id])
  end

  def authorize_team_member!
    @membership = current_user.team_memberships.find_by(
      team_id: @team.id,
      status: "approved"
    )
    return if @membership

    render json: { error: "You are not an approved member of this team." },
           status: :forbidden
  end

  def authorize_manager!
    return if approved_manager?

    render json: { error: "Only an approved team manager can record discipline." },
           status: :forbidden
  end

  def approved_manager?
    current_user.account_type == "manager" &&
      current_user.manager_verification_status == "approved" &&
      @membership&.role == "manager"
  end

  def approved_players
    User.joins(:team_memberships).where(
      team_memberships: {
        team_id: @team.id,
        role: "player",
        status: "approved"
      }
    ).distinct
  end

  def require_team_payments_plus!
    require_plus!(team: @team, feature: :team_payments)
  end

  def payment_type_for(card_type)
    {
      "yellow" => "yellow_card_fine",
      "second_yellow" => "second_yellow_fine",
      "straight_red" => "red_card_fine",
      "other" => "disciplinary_fine"
    }.fetch(card_type, "disciplinary_fine")
  end

  def record_params
    params.require(:disciplinary_record).permit(
      :match_id,
      :player_id,
      :card_type,
      :incident_minute,
      :reason,
      :notes,
      :evidence_url,
      :suspension_matches,
      :appeal_status,
      :fine_amount_pence,
      :fine_title,
      :fine_due_at
    )
  end

  def update_params
    params.require(:disciplinary_record).permit(
      :incident_minute,
      :reason,
      :notes,
      :evidence_url,
      :suspension_matches,
      :suspension_matches_remaining,
      :appeal_status
    )
  end

  def record_json(record)
    {
      id: record.id,
      team_id: record.team_id,
      match_id: record.match_id,
      player_id: record.player_id,
      card_type: record.card_type,
      incident_minute: record.incident_minute,
      reason: record.reason,
      notes: record.notes,
      evidence_url: record.evidence_url,
      suspension_matches: record.suspension_matches,
      suspension_matches_remaining: record.suspension_matches_remaining,
      appeal_status: record.appeal_status,
      player: {
        id: record.player.id,
        first_name: record.player.first_name,
        last_name: record.player.last_name
      },
      match: {
        id: record.match.id,
        opponent: record.match.opponent,
        kickoff_time: record.match.kickoff_time
      },
      payment:
        record.match_payment ?
          TeamPaymentSerializer.call(record.match_payment) : nil,
      created_at: record.created_at,
      updated_at: record.updated_at
    }
  end
end
