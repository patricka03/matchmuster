require "test_helper"

class UserMailerTest < ActionMailer::TestCase
  test "sends the player welcome email with player content and inline logo" do
    mail = UserMailer.welcome_email(build_user(account_type: "player"))

    assert_equal "Welcome to the MatchMuster family", mail.subject
    assert_equal ["player@example.com"], mail.to
    assert_equal ["support@matchmuster.uk"], mail.from

    assert_match "Hi Jordan,", mail.text_part.body.decoded
    assert_match "As a player, you can:", mail.text_part.body.decoded
    assert_match "completely free for players", mail.text_part.body.decoded
    assert_no_match "MatchMuster Plus includes", mail.text_part.body.decoded

    assert_match "As a player, you can:", mail.html_part.body.decoded
    assert_match "support@matchmuster.uk", mail.html_part.body.decoded

    assert_inline_logo(mail)
  end

  test "sends the manager welcome email with Free and Plus content" do
    mail = UserMailer.welcome_email(build_user(account_type: "manager"))

    assert_equal "Welcome to the MatchMuster family", mail.subject
    assert_equal ["manager@example.com"], mail.to
    assert_equal ["support@matchmuster.uk"], mail.from

    assert_match "Hi Jordan,", mail.text_part.body.decoded
    assert_match "With MatchMuster Free, you can:", mail.text_part.body.decoded
    assert_match "MatchMuster Plus includes:", mail.text_part.body.decoded
    assert_match "Players will never need to pay", mail.text_part.body.decoded
    assert_no_match "As a player, you can:", mail.text_part.body.decoded

    assert_match "MatchMuster Plus includes:", mail.html_part.body.decoded
    assert_match "support@matchmuster.uk", mail.html_part.body.decoded

    assert_inline_logo(mail)
  end

  test "uses a safe greeting when the first name is blank" do
    user = build_user(account_type: "player")
    user.first_name = " "

    mail = UserMailer.welcome_email(user)

    assert_match "Hi there,", mail.text_part.body.decoded
  end

  private

  def build_user(account_type:)
    User.new(
      first_name: "Jordan",
      last_name: "Taylor",
      email: "#{account_type}@example.com",
      account_type: account_type,
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  end

  def assert_inline_logo(mail)
    logo = mail.attachments[UserMailer::WELCOME_LOGO_FILENAME]

    assert_predicate logo, :present?
    assert_predicate logo, :inline?
    assert_equal "image/jpeg", logo.mime_type
    assert_predicate logo.body.decoded, :present?
    assert_match "cid:", mail.html_part.body.decoded
  end
end
