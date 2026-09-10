class ModerationAlertJob < ApplicationJob
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(report_id)
    return unless Report.exists?(report_id)

    ModerationMailer.report_received(report_id).deliver_now
  end
end
