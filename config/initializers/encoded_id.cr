MartenEncodedId.configure do |c|
  c.salt = ENV["ENCODED_ID_SALT"]? || "writebook-dev-salt"
  c.min_length = 8
  c.encoder = :hashids
end
