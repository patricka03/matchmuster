class UserMailer < ApplicationMailer
  default from: "support@matchmuster.uk"

  def welcome_email(user)
    @user = user

    mail(
      to: @user.email,
      subject: "Welcome to MatchMuster!"
    )
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
end
