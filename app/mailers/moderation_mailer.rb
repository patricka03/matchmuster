class ModerationMailer < ApplicationMailer
  def report_received(report_id)
    report = Report.find(report_id)
    recipient = ENV["MODERATION_ALERT_EMAIL"].presence || "matchmuster.dev@gmail.com"

    # Private message text and reporter identity stay in the authenticated portal.
    mail(to: recipient, subject: "MatchMuster moderation review ##{report.id}") do |format|
      format.text do
        render plain: "A new #{report.content_snapshot['trigger'] == 'user_block' ? 'block' : 'content report'} needs review.\n\n" \
          "Report ID: #{report.id}\nReason: #{report.reason}\n" \
          "Sign in to the MatchMuster developer portal and open Reports.\n" \
          "Review the preserved evidence and take appropriate action promptly.\n"
      end
    end
  end
end
