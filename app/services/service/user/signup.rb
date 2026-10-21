# Copyright (C) 2012-2026 Zammad Foundation, https://zammad-foundation.org/

class Service::User::Signup < Service::Base

  attr_reader :user_data, :resend

  def initialize(user_data:, resend: false)
    @user_data = user_data
    @resend = resend
    @path = {
      signup: 'desktop/signup/verify/',
      taken:  'desktop/reset-password/verify/'
    }
  end

  def execute
    ensure_not_import_mode!

    Service::CheckFeatureEnabled.execute(name: 'user_create_account')

    if resend
      user = ::User.find_by(email: user_data[:email].downcase)

      # The result is always positive to avoid leaking of existing user accounts.
      return true if !user || user.verified == true
    else
      if user_with_email_exists!
        raise Exceptions::UnprocessableContent, __('Email sudah terdaftar. Silakan gunakan email lain atau masuk ke akun Anda.')
      end

      PasswordPolicy.new(user_data[:password]).valid!

      user = create_user
      user.update!(verified: true)
    end

    result = ::User.signup_new_token(user)
    raise TokenGenerationError if !result || !result[:token]

    result[:url] = "#{Setting.get('http_type')}://#{Setting.get('fqdn')}/#{@path[:signup]}#{result[:token].token}"

    begin
      NotificationFactory::Mailer.notification(
        template: 'signup',
        user:     user,
        objects:  result,
      )
    rescue => e
      Rails.logger.error "Signup notification email failed (#{e.class}: #{e.message}). Ignoring error since user is already auto-verified."
    end

    true
  end

  def ensure_not_import_mode!
    return if !Setting.get('import_mode')

    message = if resend
                __('Could not send user verification email because import_mode setting is on.')
              else
                __('Could not create user and send verification email because import_mode setting is on.')
              end

    Rails.logger.error message
    raise Exceptions::UnprocessableContent, message
  end

  class TokenGenerationError < StandardError
    def initialize
      super(__('The token could not be generated.'))
    end
  end

  private

  def user_with_email_exists!
    email_val = user_data[:email].to_s.strip.downcase
    existing_user = User.find_by('LOWER(email) = :e OR LOWER(login) = :e', e: email_val)
    return false if existing_user.blank?

    true
  end

  def create_user
    user = User.new(user_data)

    user.role_ids = Role.signup_role_ids
    user.source = 'signup'
    user.skip_ensure_uniq_email = true
    user.validate!

    UserInfo.ensure_current_user_id do
      user.save!
    end

    user
  end
end
