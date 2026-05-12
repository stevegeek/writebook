# Wire our User class into marten-auth. Must run after models autoload —
# initializers run after both model and settings files, so this is safe.
Marten.settings.auth.user_model = Accounts::User
