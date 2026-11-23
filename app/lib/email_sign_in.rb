# frozen_string_literal: true

# Passwordless sign-in and sign-up, on the web (EmailCodesController) and in the app
# (Api::V1::EmailCodesController): type an email, get a six-digit code (EmailCode), enter it.
#
# Sending answers the same whether or not the address has an account, so the form never says
# which emails are on Dabble Me. The email itself differs ("sign in" or "create your account"),
# since only the inbox's owner reads it. An address with no account gets one only once its code
# is entered, so a mistyped address leaves nothing behind, and entering the code confirms the
# address (users.email_verified_at).
#
# Accounts with a password keep it: the code is another way in, not a replacement. An account
# with 2FA still needs its authenticator code after the emailed one.
module EmailSignIn
  PURPOSE = 'sign_in'

  Completed = Struct.new(:user, :created, keyword_init: true)

  # Accounts made from here on by password (the legacy sign-up forms, which don't check the
  # address) count as unclaimed until an emailed code proves the inbox. Older accounts are left
  # alone: they predate users.email_verified_at.
  UNCLAIMED_FROM = Time.utc(2026, 11, 23)

  module_function

  def normalize(email)
    EmailCode.normalize(email)
  end

  def valid_address?(email)
    email = normalize(email)
    email.match?(User::VALID_EMAIL_REGEX) && !User.blocked_email_domain?(email.split('@', 2).last)
  end

  # :sent, :invalid_email, :too_soon or :too_many.
  def send_code(email)
    email = normalize(email)
    return :invalid_email unless valid_address?(email)

    status = EmailCode.send_status(email, purpose: PURPOSE)
    return status unless status == :ok

    code = EmailCode.issue!(email, purpose: PURPOSE)
    UserMailer.sign_in_code(email, code, new_account: account_for(email).nil?).deliver_later
    :sent
  end

  # The account at this address, if there is one.
  def account_for(email)
    User.find_for_authentication(email: normalize(email))
  end

  # An account someone made with this address by password, or moved onto it by changing its
  # email, before its owner ever proved they read the inbox. Whoever made it may not own the address, so the first code sign-in wipes its
  # credentials (User#clear_credentials_for_email_claim!) and needs no 2FA code.
  def unclaimed?(user)
    user.email_verified_at.nil? && (user.created_at >= UNCLAIMED_FROM || user.email_changed_at.present?)
  end

  # The live code this matches, or nil. Check 2FA (when the account has it) before #complete!.
  def match(email, code)
    EmailCode.match(normalize(email), code, purpose: PURPOSE)
  end

  # Uses up the code and returns the account, making it when the address had none. nil when
  # the code was used meanwhile, :signups_closed once a closing is announced, or :invalid when
  # the new account won't save.
  def complete!(email_code, email, referrer: nil)
    email = normalize(email)
    user = account_for(email)
    return :signups_closed if user.nil? && SiteClosure.current
    return nil unless email_code.use!

    created = false
    unless user
      user = User.new(email: email, passwordless_signup: true, referrer: referrer)
      yield user if block_given?
      return :invalid unless save_new_account(user)

      created = true
    end
    user.clear_credentials_for_email_claim! if !created && unclaimed?(user)
    user.update_column(:email_verified_at, Time.current)
    Completed.new(user: user, created: created)
  end

  # Where the account was made (users.signup_platform, for the welcome email and Admin Stats).
  def set_platform(user, platform)
    user.signup_platform = platform
  end

  # Two requests with the same code can't both get here (EmailCode#use!), but a sign-up by
  # password for the same address can land in between.
  def save_new_account(user)
    user.save
  rescue ActiveRecord::RecordNotUnique
    false
  end
end
