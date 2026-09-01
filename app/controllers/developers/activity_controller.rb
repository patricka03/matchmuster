class Developers::ActivityController < Developers::BaseController
  def index
    activities = [
      user_activities,
      team_activities,
      fixture_activities,
      payment_activities
    ].flatten

    activities = activities
      .sort_by { |activity| activity[:occurred_at] }
      .reverse
      .first(30)

    render json: {
      activities: activities
    }, status: :ok
  end

  private

  def user_activities
    User.order(created_at: :desc).limit(10).map do |user|
      name = [user.first_name, user.last_name]
        .compact
        .join(" ")
        .strip

      name = user.email if name.blank?

      manager = user.account_type == "manager"

      {
        id: "user-#{user.id}",
        type: manager ? "manager_applied" : "player_joined",
        title: manager ? "New manager application" : "New player joined",
        description: manager ?
          "#{name} submitted a manager application." :
          "#{name} created a player account.",
        occurred_at: user.created_at
      }
    end
  end

  def team_activities
    Team.order(created_at: :desc).limit(10).map do |team|
      {
        id: "team-#{team.id}",
        type: "team_created",
        title: "New team created",
        description: "#{team.name} was added to MatchMuster.",
        occurred_at: team.created_at
      }
    end
  end

  def fixture_activities
    Match
      .includes(:team)
      .order(created_at: :desc)
      .limit(10)
      .map do |fixture|
        {
          id: "fixture-#{fixture.id}",
          type: "fixture_created",
          title: "Fixture created",
          description:
            "#{fixture.team.name} vs #{fixture.opponent} was added.",
          occurred_at: fixture.created_at
        }
      end
  end

  def payment_activities
    MatchPayment
      .includes(:user, :team, :match)
      .where(status: "paid")
      .order(updated_at: :desc)
      .limit(10)
      .map do |payment|
        player_name = [
          payment.user.first_name,
          payment.user.last_name
        ].compact.join(" ").strip

        {
          id: "payment-#{payment.id}",
          type: "payment_paid",
          title: "Team payment completed",
          description:
            "#{player_name} paid #{payment.title} for #{payment.team.name}.",
          amount_pence: payment.amount_pence,
          occurred_at: payment.updated_at
        }
      end
  end
end
