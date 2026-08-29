class NotificationEvents
  class << self
    def fixture_created(match:, actor:)
      notify_players_for_match(
        match,
        actor: actor,
        title: "New fixture against #{match.opponent}",
        message: "A new fixture has been added. Open the match to review the details.",
        notification_type: "fixture_created"
      )
    end

    def fixture_updated(match:, actor:)
      notify_players_for_match(
        match,
        actor: actor,
        title: "Fixture details updated",
        message: "The fixture against #{match.opponent} has changed. Review the latest details.",
        notification_type: "fixture_updated"
      )
    end

    def fixture_cancelled(match:, actor:)
      notify_players_for_match(
        match,
        actor: actor,
        title: "Fixture cancelled",
        message: "The fixture against #{match.opponent} has been cancelled.",
        notification_type: "fixture_cancelled"
      )
    end

    def availability_required(match:, actor:)
      notify_players_for_match(
        match,
        actor: actor,
        title: "Are you available?",
        message: "Confirm your availability for the match against #{match.opponent}.",
        notification_type: "availability_required"
      )
    end

    def player_availability_updated(
      match:,
      player:,
      status:,
      removed_from_squad: false
    )
      status_text =
        status
          .to_s
          .tr("_", " ")

      manager_message =
        "#{display_name(player)} is now #{status_text} for the match against #{match.opponent}."

      if removed_from_squad
        manager_message +=
          " They were automatically removed from the Matchday Squad."
      end

      NotificationDelivery.to_managers(
        team: match.team,
        actor: player,
        match: match,

        title:
          removed_from_squad ?
            "Player unavailable - squad updated" :
            "Player availability updated",

        message:
          manager_message,

        notification_type:
          "player_availability_updated"
      )

      return unless removed_from_squad

      NotificationDelivery.to_user(
        user: player,
        team: match.team,
        match: match,

        title:
          "Removed from Matchday Squad",

        message:
          "Because you marked yourself unavailable, you have been removed from the Matchday Squad for the match against #{match.opponent}.",

        notification_type:
          "squad_updated"
      )
    end

    def join_request_received(team:, player:)
      NotificationDelivery.to_managers(
        team: team,
        actor: player,
        title: "New player join request",
        message: "#{display_name(player)} has asked to join #{team.name}.",
        notification_type: "join_request_received"
      )
    end

    def membership_updated(
      team:,
      player:,
      manager:,
      approved:
    )
      type =
        approved ? "membership_approved" : "membership_rejected"

      title =
        approved ? "Team request approved" : "Team request update"

      message =
        if approved
          "You are now a member of #{team.name}."
        else
          "Your request to join #{team.name} was not approved."
        end

      NotificationDelivery.to_user(
        user: player,
        actor: manager,
        team: team,
        title: title,
        message: message,
        notification_type: type
      )

      return unless approved

      NotificationDelivery.to_managers(
        team: team,
        actor: player,
        except: manager,
        title: "New squad member",
        message: "#{display_name(player)} has joined #{team.name}.",
        notification_type: "player_joined"
      )
    end

    def membership_removed(team:, player:, manager:)
      NotificationDelivery.to_user(
        user: player,
        actor: manager,
        team: team,
        title: "Removed from team",
        message: "You have been removed from #{team.name} by a team manager.",
        notification_type: "team_membership_removed"
      )
    end

    def post_created(post:, actor:)
      type =
        if post.post_type == "tactical"
          "tactical_post"
        else
          "announcement"
        end

      NotificationDelivery.to_players(
        team: post.team,
        actor: actor,
        except: actor,
        post: post,
        title: post_notification_title(post),
        message: "#{display_name(actor)} posted: #{post.title}",
        notification_type: type
      )
    end

    def post_updated(post:, actor:)
      type =
        if post.post_type == "tactical"
          "tactical_post"
        else
          "announcement"
        end

      NotificationDelivery.to_players(
        team: post.team,
        actor: actor,
        except: actor,
        post: post,
        title: post_updated_notification_title(post),
        message: "#{display_name(actor)} updated: #{post.title}",
        notification_type: type
      )
    end

    def squad_not_selected(
      match:,
      actor:,
      recipient:
    )
      NotificationDelivery.to_user(
        user: recipient,
        actor: actor,
        team: match.team,
        match: match,
        title: "Not selected for this match",
        message:
          "You have not been selected for the match against #{match.opponent}.",
        notification_type: "squad_updated"
      )
    end

    def squad_published(
      match:,
      actor:,
      updated: false,
      recipient: nil
    )
      attributes = {
        actor: actor,
        match: match,

        title:
          updated ?
            "Game squad updated" :
            "Game squad selected",

        message:
          "Open this notification to see the Starting XI and bench for the match against #{match.opponent}.",

        notification_type:
          updated ?
            "squad_updated" :
            "squad_selected"
      }

      if recipient
        NotificationDelivery.to_user(
          user: recipient,
          team: match.team,
          **attributes
        )
      else
        NotificationDelivery.to_players(
          team: match.team,
          **attributes
        )
      end
    end

    def payment_requested(match_payment:, actor:)
      player = match_payment.user

      NotificationDelivery.to_user(
        user: player,
        actor: actor,
        team: match_payment.match.team,
        match: match_payment.match,
        match_payment: match_payment,
        title: "Match payment requested",
        message: "You have been requested to pay #{formatted_amount(match_payment.amount_pence)} for the upcoming match.",
        notification_type: "match_payment_requested"
      )
    end

    def payment_updated(match_payment:, actor:)
      NotificationDelivery.to_user(
        user: match_payment.user,
        actor: actor,
        team: match_payment.match.team,
        match: match_payment.match,
        match_payment: match_payment,
        title: "Match payment updated",
        message: "Your match payment is now #{formatted_amount(match_payment.amount_pence)}.",
        notification_type: "match_payment_amount_changed"
      )
    end

    def payment_waived(match_payment:, actor:)
      NotificationDelivery.to_user(
        user: match_payment.user,
        actor: actor,
        team: match_payment.match.team,
        match: match_payment.match,
        match_payment: match_payment,
        title: "Match payment waived",
        message: "Your match payment of #{formatted_amount(match_payment.amount_pence)} has been waived. You do not need to pay.",
        notification_type: "match_payment_waived"
      )
    end

    def payment_paid(match_payment:)
      player =
        match_payment.user

      amount =
        formatted_amount(
          match_payment.amount_pence
        )

      NotificationDelivery.to_user(
        user: player,
        team: match_payment.match.team,
        match: match_payment.match,
        match_payment: match_payment,
        title: "Payment received",
        message: "Your payment of #{amount} has been received.",
        notification_type: "match_payment_paid"
      )

      NotificationDelivery.to_managers(
        team: match_payment.match.team,
        actor: player,
        match: match_payment.match,
        match_payment: match_payment,
        title: "Match payment received",
        message: "#{display_name(player)} paid #{amount}.",
        notification_type: "match_payment_paid"
      )
    end

    def motm_voting_open(match:, actor:)
      notify_players_for_match(
        match,
        actor: actor,
        title: "MOTM voting is open",
        message: "Choose your standout player from the match against #{match.opponent}.",
        notification_type: "motm_voting_open"
      )
    end

    def motm_ratings_submitted(match:, voter:)
      NotificationDelivery.to_managers(
        team: match.team,
        actor: voter,
        match: match,
        title: "MOTM ratings submitted",
        message: "#{display_name(voter)} submitted player ratings for the match against #{match.opponent}.",
        notification_type: "motm_vote_received"
      )
    end

    def motm_vote_received(match:, voter:, nominee:)
      NotificationDelivery.to_managers(
        team: match.team,
        actor: voter,
        featured_user: nominee,
        match: match,
        title: "MOTM vote received",
        message: "#{display_name(voter)} voted for #{display_name(nominee)}.",
        notification_type: "motm_vote_received"
      )
    end

    def motm_announced(match:, winner:, actor:)
      NotificationDelivery.to_team(
        team: match.team,
        actor: actor,
        featured_user: winner,
        match: match,
        title: "Player of the match",
        message: "#{display_name(winner)} is your Player of the Match against #{match.opponent}.",
        notification_type: "motm_announced"
      )
    end

    def training_availability_updated(
      training:,
      player:,
      status:
    )
      status_text =
        status
          .to_s
          .tr("_", " ")

      NotificationDelivery.to_managers(
        team: training.team,
        training: training,
        actor: player,
        title: "Training availability updated",
        message:
          "#{display_name(player)} is now #{status_text} for training.",
        notification_type:
          "training_availability_updated"
      )
    end

    private

    def notify_players_for_match(match, **attributes)
      NotificationDelivery.to_players(
        team: match.team,
        match: match,
        **attributes
      )
    end

    def display_name(user)
      full_name =
        [user.first_name, user.last_name]
          .compact
          .join(" ")
          .strip

      full_name.presence || user.email
    end

    def post_notification_title(post)
      if post.post_type == "tactical"
        "New tactical post"
      else
        "New team announcement"
      end
    end

    def post_updated_notification_title(post)
      if post.post_type == "tactical"
        "Tactical post updated"
      else
        "Team announcement updated"
      end
    end

    def formatted_amount(amount_pence)
      format(
        "£%.2f",
        amount_pence.to_i / 100.0
      )
    end
  end
end
