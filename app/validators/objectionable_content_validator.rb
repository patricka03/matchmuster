class ObjectionableContentValidator <
      ActiveModel::EachValidator
  def validate_each(
    record,
    attribute,
    value
  )
    phrase =
      ContentScreening.detected_phrase(
        value
      )

    return unless phrase

    record.errors.add(
      attribute,
      "contains language that is not allowed"
    )
  end
end
