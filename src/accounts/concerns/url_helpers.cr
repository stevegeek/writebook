module Accounts
  # Handler-level URL helpers. Cross-cutting (used by accounts/* and books/*),
  # so it lives under accounts/concerns alongside AuthenticationHelpers.
  #
  # `absolute_url` builds a fully-qualified URL ("scheme://host/path") for a
  # named route, replacing the duplicated `"#{request.scheme}://#{request.host}"
  # + Marten.routes.reverse(...)` pattern.
  #
  # Usage:
  #
  #   class FooHandler < Marten::Handler
  #     include Accounts::UrlHelpers
  #
  #     def get
  #       url = absolute_url("books:show", id: book.pk!)
  #       ...
  #     end
  #   end
  module UrlHelpers
    protected def absolute_url(route_name : String, **kwargs) : String
      "#{request.scheme}://#{request.host}#{Marten.routes.reverse(route_name, **kwargs)}"
    end

    # Returns just the "scheme://host" prefix — useful when callers need to
    # append a path they already have in hand (e.g. a token-derived path).
    protected def absolute_url_base : String
      "#{request.scheme}://#{request.host}"
    end
  end
end
