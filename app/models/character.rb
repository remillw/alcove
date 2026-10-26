class Character < ApplicationRecord
  has_many :conversations, dependent: :restrict_with_exception

  scope :published, -> { where(published: true).order(:position) }

  validates :slug, :name, :role, :tagline, :persona, :boundaries, :greeting, :model, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }

  def to_param = slug
  def first_name = name.split.first

  # avatar drawn in CSS from the slug: stable, no image to host
  def avatar_tint = slug.sum % 8
  def avatar_motif = %w[stripes dots rings plain][slug.sum % 4]
end
