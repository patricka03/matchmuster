class DeveloperPlatformAudit
  class << self
    def record!(
      developer:,
      action_type:,
      notes:,
      target: nil,
      metadata: {}
    )
      DeveloperPlatformAction.create!(
        developer: developer,
        action_type: action_type,
        target_type: target&.class&.name,
        target_id: target&.id,
        notes: notes.to_s.strip.presence || "Developer action",
        metadata: metadata || {}
      )
    end
  end
end
