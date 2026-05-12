module Accounts
  # Generates expiring tokens for transferring user-administered books to
  # a different account. Wraps marten-signed-id with a fixed "transfer"
  # purpose and a 4-hour expiry. Mirrors Rails User::Transferable.
  #
  # Host model must `include MartenSignedId::ModelMixin` before including
  # this concern — Transferable's `find_by_transfer_id` delegates to the
  # mixin-supplied `find_signed`.
  module Transferable
    TRANSFER_LINK_EXPIRY_DURATION = 4.hours

    macro included
      def self.find_by_transfer_id(id : ::String) : self?
        find_signed(id, purpose: "transfer")
      end
    end

    def transfer_id : ::String
      signed_id(purpose: "transfer", expires_in: TRANSFER_LINK_EXPIRY_DURATION)
    end
  end
end
