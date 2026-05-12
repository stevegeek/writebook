# `script/manage reset_passwords` — resets every active user's password.
#
# Dev convenience. Run on a local DB only. Defaults to "password123";
# override with `--password=<value>`.
#
#   script/manage reset_passwords
#   script/manage reset_passwords --password=hunter2
#
# Uses `MartenAuth::User#set_password` so the hash format matches what
# the sign-in handler verifies.
class Accounts::ResetPasswordsCommand < Marten::CLI::Command
  command_name :reset_passwords
  help "Reset every active user's password (dev only)"

  @password : String = "password123"

  def setup
    on_option_with_arg("p", "password", "PASSWORD", "Password to set (default: password123)") do |value|
      @password = value
    end
  end

  def run
    users = ::Accounts::User.filter(active: true).to_a
    if users.empty?
      print(style("No active users found.", fore: :yellow))
      return
    end

    users.each do |user|
      user.set_password(@password)
      user.save!
      print("  ✓ #{user.email}")
    end

    print(style("Reset #{users.size} password(s) to \"#{@password}\".", fore: :green))
  end
end
