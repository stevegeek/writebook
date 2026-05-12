module Accounts
  # GET  /account/custom_styles — admin-only CSS editor.
  # POST /account/custom_styles — save updated CSS.
  #
  # Mirrors Rails' Accounts::CustomStylesController. Persists `custom_styles`
  # on the singleton `Account`; the saved value is injected into base.html
  # `<head>` via `Accounts::AuthContextProducer#account_custom_styles`.
  # Empty submissions clear the column (stored as NULL) so the `{% if %}`
  # guard in base.html drops the `<style>` tag.
  class CustomStylesEditHandler < Marten::Handlers::Schema
    include AuthenticationHelpers

    schema CustomStylesSchema
    template_name "custom_styles/edit.html"

    before_dispatch :require_authentication
    before_dispatch :require_admin
    before_render :inject_account

    # Pre-fill the textarea on GET (and re-show prior input on invalid POST)
    # by seeding the schema's `initial` from the saved Account value.
    def initial_data
      Marten::Schema::DataHash{
        "custom_styles" => Account.first!.custom_styles || "",
      }
    end

    def process_valid_schema
      css = schema.validated_data["custom_styles"]?.try(&.as(String)) || ""
      Account.first!.update!(custom_styles: css.empty? ? nil : css)
      redirect(Marten.routes.reverse("accounts:custom_styles_edit"))
    end

    private def inject_account : Nil
      context[:account] = Account.first!
    end
  end
end
