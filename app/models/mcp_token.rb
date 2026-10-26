class McpToken < ApplicationRecord
  PREFIX = "alc_"

  # returns the clear token once; only its digest is kept
  def self.issue!(name)
    token = PREFIX + SecureRandom.base58(32)
    create!(name:, digest: digest(token))
    token
  end

  def self.authenticate(token)
    return if token.blank?
    where(revoked_at: nil).find_by(digest: digest(token))&.tap { _1.update_column(:last_used_at, Time.current) }
  end

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token)
end
