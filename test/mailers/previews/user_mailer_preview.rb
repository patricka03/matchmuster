# Preview all emails at http://localhost:3000/rails/mailers/user_mailer
class UserMailerPreview < ActionMailer::Preview
  def player_welcome_email
    UserMailer.welcome_email(
      preview_user(account_type: "player")
    )
  end

  def manager_welcome_email
    UserMailer.welcome_email(
      preview_user(account_type: "manager")
    )
  end

  private

  def preview_user(account_type:)
    User.new(
      first_name: "Jordan",
      last_name: "Taylor",
      email: "#{account_type}@example.com",
      account_type: account_type,
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  end
end
