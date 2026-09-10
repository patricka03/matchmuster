class ReportTarget
  CLASSES = { "Post" => Post, "MatchRating" => MatchRating, "Message" => Message }.freeze

  def self.author(content)
    case content
    when Post then content.user
    when MatchRating then content.rater
    when Message then content.sender
    end
  end

  def self.accessible_to?(content, user)
    team_id = case content
              when Post then content.team_id
              when MatchRating then content.match.team_id
              when Message then content.conversation.team_id
              end

    return false unless team_id && user.team_memberships.exists?(team_id: team_id, status: "approved")
    # Membership of the same team never grants access to somebody else's DMs.
    return content.conversation.participant?(user) if content.is_a?(Message)

    true
  end
end
