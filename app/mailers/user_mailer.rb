class UserMailer < ApplicationMailer
  default from: "support@matchmuster.uk"

  WELCOME_LOGO_FILENAME = "matchmuster-logo.jpeg".freeze
  WELCOME_LOGO_PATH = Rails.root.join(
    "app/assets/images",
    WELCOME_LOGO_FILENAME
  ).freeze

  def welcome_email(user)
    @user = user
    @first_name = @user.first_name.to_s.strip.presence || "there"

    attach_welcome_logo

    template =
      if @user.manager?
        "manager_welcome_email"
      else
        "player_welcome_email"
      end

    mail(
      to: @user.email,
      subject: "Welcome to the MatchMuster family"
    ) do |format|
      format.html do
        render(
          template: "user_mailer/#{template}",
          formats: [:html]
        )
      end

      format.text do
        render(
          template: "user_mailer/#{template}",
          formats: [:text]
        )
      end
    end
  end

  def manager_approved_email(user)
    @user = user

    mail(
      to: @user.email,
      subject: "Your MatchMuster manager account has been approved!"
    )
  end

  def manager_rejected_email(email:, first_name:)
    @first_name = first_name.to_s.strip.presence || "there"

    mail(
      to: email,
      subject: "Your MatchMuster manager application"
    )
  end

  private

  def attach_welcome_logo
    attachments.inline[WELCOME_LOGO_FILENAME] = {
      mime_type: "image/jpeg",
      content: File.binread(WELCOME_LOGO_PATH)
    }
  end
end
