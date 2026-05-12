module Accounts
  # App version exposed in the UI footer (sessions/new, users/index — mirrors
  # Rails' `version_badge` helper which reads `Rails.application.config.app_version`,
  # set from the `APP_VERSION` env var on boot).
  APP_VERSION = ENV["APP_VERSION"]? || "0"

  # Injects auth-related context variables into every template automatically.
  # Register this in config/settings/base.cr by appending
  #   Accounts::AuthContextProducer
  # to the config.templates.context_producers array.
  class AuthContextProducer < Marten::Template::ContextProducer
    def produce(request : Marten::HTTP::Request? = nil)
      return {"app_version" => Marten::Template::Value.from(APP_VERSION)} of String => Marten::Template::Value if request.nil?

      user = request.user.try(&.as(::Accounts::User))
      account = ::Accounts::Account.first

      # `account_custom_styles` is rendered into base.html `<head>` behind a
      # `{% if account_custom_styles %}` guard. Marten templates treat an
      # empty string as truthy, so we must keep this `nil` when the account
      # has no saved CSS — otherwise base.html emits an empty `<style></style>`.
      custom_styles = account.try(&.custom_styles)
      custom_styles = nil if custom_styles.try(&.empty?)

      {
        "signed_in"             => Marten::Template::Value.from(!user.nil?),
        "current_user_name"     => Marten::Template::Value.from(user.try(&.name) || ""),
        "current_user_admin"    => Marten::Template::Value.from(user.try(&.administrator?) || false),
        "current_user_id"       => Marten::Template::Value.from(user.try(&.id)),
        "account_custom_styles" => Marten::Template::Value.from(custom_styles),
        "app_version"           => Marten::Template::Value.from(APP_VERSION),
      }
    end
  end
end
