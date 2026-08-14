class BackgroundJobHealthCheckJob < ApplicationJob
  queue_as :default

  def perform(message = "MATCHMUSTER_BACKGROUND_JOB_OK")
    output = <<~MESSAGE

      ========================================
      #{message}
      Background job executed at: #{Time.current}
      ========================================

    MESSAGE

    puts output
    Rails.logger.info(output)
  end
end
