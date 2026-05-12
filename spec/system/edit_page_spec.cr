require "./spec_helper"

# Port of writebook-rails/test/system/edit_page_test.rb.
#
# The Rails original drives the `<house-md>` form-associated custom element via
# Capybara + `execute_script` setting `.value`. In our test environment, asset
# routes aren't mounted (Marten gates `Marten::Handlers::Defaults::Development::ServeAsset`
# behind `Marten.env.development?`), so the house-md JS never loads — meaning
# `<house-md>` is an HTMLUnknownElement that doesn't participate in form data.
# Setting `.value` on it is a no-op and a form submit drops body entirely.
#
# Instead we POST the edit ourselves via `fetch()`, lifting the CSRF token off
# the rendered form. The data path is identical to what house-md would send
# once its JS attached; we're just bypassing the custom-element layer that
# can't be loaded in test env. The render assertions on `.house-md-content`
# below still validate the show-page Markdown pipeline.
describe "Edit page (system)" do
  it "saves new body content and renders it on show" do
    Spec::Factories.create_account
    kevin = Spec::Factories.create_user(email: "kevin@example.com")
    handbook = Spec::Factories.create_book(title: "Handbook", editor: kevin)
    welcome = Spec::Factories.create_page_leaf(book: handbook, title: "Welcome", body: "Old body")
    page_pk = welcome.leafable_id.not_nil!

    sign_in kevin
    visit "/pages/#{welcome.pk}/edit"
    assert_selector "house-md"

    new_body = "Welcome to the handbook! This is the **first** page."
    execute_script <<-JS
      const form = document.getElementById('leafable-editor');
      const fd = new FormData();
      fd.append('title', 'Welcome');
      fd.append('body', #{new_body.to_json});
      fd.append('csrftoken', form.querySelector('[name="csrftoken"]').value);
      // Explicit Accept: text/html bypasses the `request.turbo?` 204 branch
      // (turbo? matches */* by default — a marten-turbo gotcha).
      window.__edit_done = false;
      fetch(form.action, {
        method: 'POST',
        body: fd,
        credentials: 'same-origin',
        headers: { 'Accept': 'text/html' },
      }).then(r => { window.__edit_status = r.status; window.__edit_done = true; });
    JS

    wait_until("fetch never completed") do
      execute_script("return JSON.stringify(window.__edit_done);") == "true"
    end
    wait_until("page body never persisted") do
      page = Books::Leafables::Page.get(pk: page_pk)
      page.try(&.body.try(&.content)) == new_body
    end

    # Marten port renders markdown server-side via MartenMarkdown::Renderer
    # into a `.page--page` div (Rails' equivalent on the show page is the
    # client-side `<house-md-content>` rendering — different mechanism, same
    # user-visible result).
    visit "/pages/#{welcome.pk}"
    assert_selector ".page--page", text: "Welcome to the handbook!"
    assert_selector ".page--page strong", text: "first"
  end
end
