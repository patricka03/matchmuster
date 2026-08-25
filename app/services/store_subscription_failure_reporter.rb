require "json"

class StoreSubscriptionFailureReporter
  class << self
    def call(
      job_name:,
      record_type:,
      record_id:,
      error:,
      logger: Rails.logger
    )
      logger.error(
        JSON.generate(
          event: "store_subscription_job_exhausted",
          job: job_name.to_s,
          record_type: record_type.to_s,
          record_id: record_id,
          error_class: error.class.name
        )
      )
    end
  end
end
