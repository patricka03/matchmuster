class TeamPaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_team
  before_action :authorize_team_member!
  before_action :set_payment,
                only: %i[
                  show update destroy checkout request_cash_confirmation
                  record_payment waive remind refund add_to_finance mark_league_settled
                  ask_manager receipt
                ]
  before_action :authorize_manager!,
                only: %i[
                  context create update destroy summary record_payment waive remind refund
                  add_to_finance mark_league_settled
                ]
  before_action :authorize_payment_owner!,
                only: %i[
                  show checkout request_cash_confirmation ask_manager receipt
                ]
  before_action :require_payment_analytics_plus!, only: :summary
  before_action :require_club_finance_plus!, only: :add_to_finance
  before_action :require_team_payments_plus_for_manager!, only: %i[index show receipt]
  before_action :require_team_payments_plus!,
                only: %i[
                  context create update destroy record_payment waive remind refund
                  mark_league_settled
                ]

  def index
    unless approved_manager?
      @team.match_payments
           .where(user: current_user, viewed_at: nil)
           .update_all(viewed_at: Time.current)
    end

    payments = payment_scope
      .includes(:user, :match, :disciplinary_record)
      .order(created_at: :desc)

    payments = payments.where(status: params[:status]) if params[:status].present?
    payments = payments.where(payment_type: params[:payment_type]) if params[:payment_type].present?

    render json: {
      payments: payments.limit(500).map { |payment| TeamPaymentSerializer.call(payment) }
    }, status: :ok
  end

  def show
    mark_viewed!

    render json: {
      payment: TeamPaymentSerializer.call(@payment.reload)
    }, status: :ok
  end

  def context
    players = approved_players.order(:first_name, :last_name)
    matches = @team.matches.order(kickoff_time: :desc).limit(100)

    render json: {
      payment_types: MatchPayment::TYPE_LABELS,
      fine_types: MatchPayment::FINE_TYPES,
      players: players.map { |player| user_json(player) },
      matches: matches.map { |match| match_json(match) },
      plus: {
        payment_analytics: PlusAccess.allowed?(team: @team, feature: :payment_analytics),
        saved_payment_templates: PlusAccess.allowed?(team: @team, feature: :saved_payment_templates),
        recurring_payments: PlusAccess.allowed?(team: @team, feature: :recurring_payments),
        automatic_payment_reminders: PlusAccess.allowed?(team: @team, feature: :automatic_payment_reminders),
        club_finance: PlusAccess.allowed?(team: @team, feature: :club_finance)
      }
    }, status: :ok
  end

  def create
    attributes = create_payment_params
    payment_type = attributes[:payment_type].presence || "match_sub"
    match = find_optional_match(attributes[:match_id])
    recipients = resolve_recipients(attributes, match, payment_type)

    if recipients.empty?
      return render json: {
        error: "Select at least one approved player."
      }, status: :unprocessable_entity
    end

    created = []
    failures = []

    MatchPayment.transaction do
      recipients.each do |player|
        payment = @team.match_payments.new(
          user: player,
          match: match,
          requested_by: current_user,
          payment_type: payment_type,
          title: attributes[:title],
          description: attributes[:description],
          amount_pence: attributes[:amount_pence],
          due_at: attributes[:due_at]
        )

        if payment_type == "match_sub" &&
           match&.match_payments&.where(user: player, payment_type: "match_sub")&.exists?
          failures << {
            user_id: player.id,
            errors: ["already has a Match Subs request for this match"]
          }
          next
        end

        if payment.save
          created << payment
          NotificationEvents.payment_requested(
            match_payment: payment,
            actor: current_user
          )
        else
          failures << {
            user_id: player.id,
            errors: payment.errors.full_messages
          }
        end
      end

      raise ActiveRecord::Rollback if created.empty? && failures.any?
    end

    status = failures.empty? ? :created : :multi_status

    render json: {
      message: "#{created.length} payment request(s) sent.",
      created_count: created.length,
      failed_count: failures.length,
      failures: failures,
      payments: created.map { |payment| TeamPaymentSerializer.call(payment) }
    }, status: status
  rescue ActiveRecord::RecordNotFound => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def update
    unless %w[pending cash_pending partially_paid].include?(@payment.status)
      return render json: {
        error: "Only outstanding payments can be edited."
      }, status: :unprocessable_entity
    end

    unless checkout_clear?
      return render json: { error: "Stripe is confirming this payment. Please refresh shortly." },
             status: :conflict
    end

    attributes = update_payment_params

    if @payment.status == "partially_paid" &&
       attributes[:amount_pence].present? &&
       attributes[:amount_pence].to_i == @payment.amount_paid_pence
      attributes[:status] = "paid"
      attributes[:paid_at] = Time.current
    end

    if @payment.update(attributes)
      NotificationEvents.payment_updated(
        match_payment: @payment,
        actor: current_user
      )

      render json: {
        payment: TeamPaymentSerializer.call(@payment)
      }, status: :ok
    else
      render json: { errors: @payment.errors.full_messages },
             status: :unprocessable_entity
    end
  end

  def destroy
    unless %w[pending cash_pending].include?(@payment.status)
      return render json: {
        error: "Only outstanding requests can be cancelled."
      }, status: :unprocessable_entity
    end

    unless checkout_clear?
      return render json: { error: "Stripe is confirming this payment. Please refresh shortly." },
             status: :conflict
    end

    @payment.update!(
      status: "cancelled",
      cancelled_at: Time.current,
      paid_at: nil,
      cash_confirmation_requested_at: nil
    )

    NotificationEvents.payment_cancelled(
      match_payment: @payment,
      actor: current_user
    )

    render json: {
      payment: TeamPaymentSerializer.call(@payment)
    }, status: :ok
  end

  def summary
    payments = @team.match_payments

    by_type = MatchPayment::TYPE_LABELS.each_with_object({}) do |(type, label), result|
      scope = payments.where(payment_type: type)
      result[type] = summary_row(scope).merge(label: label)
    end

    render json: summary_row(payments).merge(
      by_type: by_type,
      overdue_count: payments.outstanding.where("due_at < ?", Time.current).count,
      cash_confirmation_count: payments.where(status: "cash_pending").count
    ), status: :ok
  end

  def checkout
    unless @payment.outstanding?
      return render json: { error: "This payment is no longer outstanding." },
             status: :unprocessable_entity
    end

    if @team.stripe_account_id.blank?
      return render json: { error: "This team has not connected Stripe." },
             status: :unprocessable_entity
    end

    account = Stripe::Account.retrieve(@team.stripe_account_id)

    unless account.charges_enabled
      return render json: {
        error: "This team's Stripe account is not ready to accept payments."
      }, status: :unprocessable_entity
    end

    frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:5173").delete_suffix("/")
    checkout_session = nil

    @payment.with_lock do
      if @payment.stripe_checkout_session_id.present?
        existing = Stripe::Checkout::Session.retrieve(
          @payment.stripe_checkout_session_id,
          { stripe_account: @team.stripe_account_id }
        )

        if existing.status == "open" && existing.url.present?
          checkout_session = existing
        elsif existing.status == "complete"
          return render json: {
            error: "Stripe is confirming this payment. Please refresh shortly."
          }, status: :accepted
        end
      end

      unless checkout_session
        checkout_session = Stripe::Checkout::Session.create(
          {
            mode: "payment",
            line_items: [{
              price_data: {
                currency: "gbp",
                unit_amount: @payment.amount_outstanding_pence,
                product_data: { name: @payment.title }
              },
              quantity: 1
            }],
            success_url: "#{frontend_url}/teams/#{@team.id}/payments?payment=success",
            cancel_url: "#{frontend_url}/teams/#{@team.id}/payments?payment=cancelled",
            metadata: { match_payment_id: @payment.id.to_s },
            payment_intent_data: {
              metadata: { match_payment_id: @payment.id.to_s }
            }
          },
          {
            stripe_account: @team.stripe_account_id,
            idempotency_key: checkout_idempotency_key
          }
        )

        @payment.update!(stripe_checkout_session_id: checkout_session.id)
      end
    end

    render json: {
      checkout_url: checkout_session.url,
      checkout_session_id: checkout_session.id
    }, status: :ok
  rescue Stripe::StripeError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def request_cash_confirmation
    unless @payment.outstanding?
      return render json: { error: "This payment is no longer outstanding." },
             status: :unprocessable_entity
    end

    unless checkout_clear?
      return render json: { error: "Stripe is confirming this payment. Please refresh shortly." },
             status: :conflict
    end

    @payment.update!(
      status: "cash_pending",
      cash_confirmation_requested_at: Time.current
    )

    NotificationEvents.payment_cash_confirmation_requested(
      match_payment: @payment,
      actor: current_user
    )

    render json: { payment: TeamPaymentSerializer.call(@payment) }, status: :ok
  end

  def record_payment
    unless @payment.outstanding?
      return render json: { error: "This payment is no longer outstanding." },
             status: :unprocessable_entity
    end

    unless checkout_clear?
      return render json: { error: "Stripe is confirming this payment. Please refresh shortly." },
             status: :conflict
    end

    @payment.with_lock do
      @payment.record_payment!(
        amount_pence: record_payment_params[:amount_pence],
        method: record_payment_params[:payment_method]
      )
    end

    NotificationEvents.payment_marked_paid_manually(
      match_payment: @payment,
      actor: current_user
    )

    render json: { payment: TeamPaymentSerializer.call(@payment) }, status: :ok
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def waive
    unless %w[pending cash_pending].include?(@payment.status)
      return render json: { error: "Only an outstanding payment can be waived." },
             status: :unprocessable_entity
    end

    unless checkout_clear?
      return render json: { error: "Stripe is confirming this payment. Please refresh shortly." },
             status: :conflict
    end

    @payment.update!(
      status: "waived",
      waived_at: Time.current,
      paid_at: nil,
      cash_confirmation_requested_at: nil
    )

    NotificationEvents.payment_waived(
      match_payment: @payment,
      actor: current_user
    )

    render json: { payment: TeamPaymentSerializer.call(@payment) }, status: :ok
  end

  def remind
    unless @payment.outstanding?
      return render json: { error: "Only an outstanding payment can be reminded." },
             status: :unprocessable_entity
    end

    NotificationDelivery.to_user(
      user: @payment.user,
      actor: current_user,
      team: @team,
      match: @payment.match,
      match_payment: @payment,
      title: "Payment reminder",
      message: "#{format_amount(@payment.amount_outstanding_pence)} for #{@payment.title} is still outstanding.",
      notification_type: "match_payment_reminder"
    )

    render json: { message: "Reminder sent." }, status: :ok
  end

  def refund
    unless @payment.status == "paid"
      return render json: { error: "Only a paid payment can be refunded." },
             status: :unprocessable_entity
    end

    refund_amount = Integer(
      refund_params[:amount_pence].presence || @payment.amount_paid_pence
    )

    refundable_amount =
      @payment.amount_paid_pence - @payment.refunded_amount_pence

    unless refund_amount.positive? && refund_amount <= refundable_amount
      return render json: { error: "Enter a valid refund amount." },
             status: :unprocessable_entity
    end

    if @payment.stripe_payment_intent_id.present?
      Stripe::Refund.create(
        {
          payment_intent: @payment.stripe_payment_intent_id,
          amount: refund_amount
        },
        { stripe_account: @team.stripe_account_id }
      )
    end

    total_refunded = @payment.refunded_amount_pence + refund_amount
    fully_refunded = total_refunded == @payment.amount_paid_pence

    @payment.update!(
      refunded_amount_pence: total_refunded,
      refunded_at: Time.current,
      status: fully_refunded ? "refunded" : "paid"
    )

    reconcile_linked_finance_entry!

    NotificationEvents.payment_refunded(
      match_payment: @payment,
      actor: current_user,
      amount_pence: refund_amount
    )

    render json: { payment: TeamPaymentSerializer.call(@payment) }, status: :ok
  rescue ArgumentError, Stripe::StripeError => error
    render json: { error: error.message }, status: :unprocessable_entity
  end

  def add_to_finance
    if @payment.status != "paid"
      return render json: { error: "Only a paid payment can be added to Club Finance." },
             status: :unprocessable_entity
    end

    if @payment.payment_type == "match_sub"
      return render json: {
        error: "Paid Match Subs are already included automatically in Club Finance."
      }, status: :unprocessable_entity
    end

    existing = @team.team_finance_entries.find_by(
      category: "Team payment",
      description: finance_description
    )

    entry = existing || @team.team_finance_entries.create!(
      created_by: current_user,
      match: @payment.match,
      entry_type: "income",
      category: "Team payment",
      description: finance_description,
      amount_pence: @payment.amount_paid_pence - @payment.refunded_amount_pence,
      occurred_on: (@payment.paid_at || Time.current).to_date
    )

    render json: {
      message: existing ? "This payment is already in Club Finance." : "Payment added to Club Finance.",
      finance_entry_id: entry.id
    }, status: :ok
  end

  def mark_league_settled
    unless @payment.fine? && @payment.status == "paid"
      return render json: {
        error: "Only a paid player fine can be marked as passed to the league."
      }, status: :unprocessable_entity
    end

    @payment.update!(league_settled_at: Time.current)
    render json: { payment: TeamPaymentSerializer.call(@payment) }, status: :ok
  end

  def ask_manager
    manager = @team.canonical_owner || approved_managers.first

    unless manager && manager.id != current_user.id
      return render json: { error: "No approved manager is available." },
             status: :unprocessable_entity
    end

    conversation = Conversation.direct_between!(
      team: @team,
      first_user: current_user,
      second_user: manager
    )

    message = conversation.messages.create!(
      sender: current_user,
      body: "Question about #{@payment.title} (#{format_amount(@payment.amount_pence)}): " \
            "#{ask_manager_params[:message]}"
    )

    NotificationDelivery.to_user(
      user: manager,
      actor: current_user,
      featured_user: current_user,
      team: @team,
      conversation: conversation,
      title: "Payment question",
      message: message.body.truncate(140),
      notification_type: "direct_message"
    )

    render json: {
      conversation_id: conversation.id,
      message_id: message.id
    }, status: :created
  end

  def receipt
    unless %w[paid refunded].include?(@payment.status)
      return render json: { error: "A receipt is available after payment." },
             status: :unprocessable_entity
    end

    render json: {
      receipt: {
        reference: "MM-PAY-#{@payment.id}",
        team_name: @team.name,
        player: user_json(@payment.user),
        title: @payment.title,
        payment_type: @payment.payment_type,
        amount_pence: @payment.amount_pence,
        amount_paid_pence: @payment.amount_paid_pence,
        refunded_amount_pence: @payment.refunded_amount_pence,
        payment_method: @payment.payment_method,
        paid_at: @payment.paid_at,
        match: match_json(@payment.match)
      }
    }, status: :ok
  end

  private

  def set_team
    @team = Team.find(params[:team_id])
  end

  def set_payment
    @payment = @team.match_payments.find(params[:id])
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

    render json: { error: "Only an approved team manager can manage payments." },
           status: :forbidden
  end

  def authorize_payment_owner!
    return if approved_manager? || @payment.user_id == current_user.id

    render json: { error: "You can only access your own payment." },
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

  def approved_managers
    User.joins(:team_memberships).where(
      account_type: "manager",
      manager_verification_status: "approved",
      team_memberships: {
        team_id: @team.id,
        role: "manager",
        status: "approved"
      }
    ).distinct
  end

  def payment_scope
    approved_manager? ? @team.match_payments : @team.match_payments.where(user: current_user)
  end

  def resolve_recipients(attributes, match, payment_type)
    scope = attributes[:recipient_scope].presence || "selected"

    case scope
    when "all_players"
      approved_players.to_a
    when "selected_squad"
      return [] unless match

      approved_players.where(id: match.squad_selections.select(:user_id)).to_a
    when "selected"
      ids = Array(attributes[:user_ids]).compact_blank
      approved_players.where(id: ids).to_a
    else
      raise ActiveRecord::RecordNotFound, "Unknown recipient selection."
    end.tap do |players|
      if MatchPayment::FINE_TYPES.include?(payment_type) && players.length != 1
        raise ActiveRecord::RecordNotFound, "A player fine must be sent to one player."
      end
    end
  end

  def find_optional_match(match_id)
    return nil if match_id.blank?

    @team.matches.find(match_id)
  end

  def mark_viewed!
    return unless @payment.user_id == current_user.id && @payment.viewed_at.blank?

    @payment.update_column(:viewed_at, Time.current)
  end

  def summary_row(scope)
    {
      total_requested_pence: scope.sum(:amount_pence),
      total_paid_pence: scope.sum(:amount_paid_pence),
      total_refunded_pence: scope.sum(:refunded_amount_pence),
      total_outstanding_pence: scope.outstanding.sum(
        Arel.sql("amount_pence - amount_paid_pence")
      ),
      total_waived_pence: scope.where(status: "waived").sum(:amount_pence),
      payment_count: scope.count
    }
  end

  def checkout_idempotency_key
    [
      "team-payment-checkout",
      @payment.id,
      @payment.amount_outstanding_pence,
      @payment.updated_at.to_i,
      @payment.updated_at.usec
    ].join("-")
  end

  def checkout_clear?
    return true if @payment.stripe_checkout_session_id.blank?

    session = Stripe::Checkout::Session.retrieve(
      @payment.stripe_checkout_session_id,
      { stripe_account: @team.stripe_account_id }
    )

    case session.status
    when "open"
      Stripe::Checkout::Session.expire(
        session.id,
        {},
        { stripe_account: @team.stripe_account_id }
      )
      @payment.update_column(:stripe_checkout_session_id, nil)
      true
    when "expired"
      @payment.update_column(:stripe_checkout_session_id, nil)
      true
    else
      false
    end
  rescue Stripe::StripeError => error
    Rails.logger.error("[Team payment checkout cancellation] #{error.message}")
    false
  end

  def finance_description
    "Payment ##{@payment.id}: #{@payment.title}".truncate(180)
  end

  def reconcile_linked_finance_entry!
    entry = @team.team_finance_entries.find_by(
      category: "Team payment",
      description: finance_description
    )
    return unless entry

    net_amount = @payment.amount_paid_pence - @payment.refunded_amount_pence
    net_amount.positive? ? entry.update!(amount_pence: net_amount) : entry.destroy!
  end

  def format_amount(pence)
    format("£%.2f", pence.to_i / 100.0)
  end

  def user_json(user)
    {
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name
    }
  end

  def match_json(match)
    return nil unless match

    {
      id: match.id,
      opponent: match.opponent,
      kickoff_time: match.kickoff_time
    }
  end

  def create_payment_params
    params.require(:payment).permit(
      :payment_type,
      :title,
      :description,
      :amount_pence,
      :due_at,
      :match_id,
      :recipient_scope,
      user_ids: []
    )
  end

  def update_payment_params
    params.require(:payment).permit(
      :title,
      :description,
      :amount_pence,
      :due_at
    )
  end

  def record_payment_params
    params.require(:payment).permit(:amount_pence, :payment_method)
  end

  def refund_params
    params.require(:payment).permit(:amount_pence)
  end

  def ask_manager_params
    params.require(:payment).permit(:message)
  end

  def require_payment_analytics_plus!
    require_plus!(team: @team, feature: :payment_analytics)
  end

  def require_club_finance_plus!
    require_plus!(team: @team, feature: :club_finance)
  end

  def require_team_payments_plus!
    require_plus!(team: @team, feature: :team_payments)
  end

  def require_team_payments_plus_for_manager!
    return unless approved_manager?

    require_team_payments_plus!
  end
end
