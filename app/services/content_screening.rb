class ContentScreening
  DEFAULT_BLOCKED_PHRASES = [
    "kill yourself",
    "go kill yourself"
  ].freeze

  class << self
    def detected_phrase(text)
      normalised_text =
        normalise(
          text
        )

      blocked_phrases.find do |phrase|
        " #{normalised_text} "
          .include?(
            " #{phrase} "
          )
      end
    end

    private

    def blocked_phrases
      configured_terms =
        ENV
          .fetch(
            "MODERATION_BLOCKED_TERMS",
            ""
          )
          .split(",")
          .filter_map do |term|
            normalised =
              normalise(
                term
              )

            normalised.presence
          end

      (
        DEFAULT_BLOCKED_PHRASES +
        configured_terms
      ).uniq
    end

    def normalise(text)
      text
        .to_s
        .downcase
        .gsub(
          /[^a-z0-9\s]/,
          " "
        )
        .squish
    end
  end
end
