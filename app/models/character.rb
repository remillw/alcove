class Character < ApplicationRecord
  has_many :conversations, dependent: :restrict_with_exception

  scope :published, -> { where(published: true).order(:position) }

  validates :slug, :name, :role, :tagline, :persona, :boundaries, :greeting, :model, presence: true
  validates :slug, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }

  def to_param = slug
  def first_name = name.split.first

  LOCALIZED = %w[role tagline greeting starters statuses returns showcase sample_lines boundaries traits].freeze

  # the French version when there is one, the English text otherwise
  LOCALIZED.each do |field|
    define_method(field) do
      value = I18n.locale == :fr ? translations.dig("fr", field) : nil
      value.presence || self[field]
    end
  end

  # public biography (the persona is the model's brief, in English and second person: never shown)
  def bio = translations.dig(I18n.locale.to_s, "bio").presence || translations.dig("en", "bio").presence || tagline

  KEEPSAKES = {
    "reading_pile" => { name: "Reading pile", short: "Pile", verb: "added to your pile" },
    "recipe_cards" => { name: "Recipe cards", short: "Recipes", verb: "wrote a recipe card" },
    "sky_log" => { name: "Sky log", short: "Sky log", verb: "noted in your sky log" },
    "case_file" => { name: "Case file", short: "Case", verb: "added to the case file" },
    "corrections" => { name: "Corrections notebook", short: "Notes", verb: "noted a correction" },
    "week" => { name: "Your week", short: "Week", verb: "pinned to your week" }
  }.freeze

  def status_now = statuses[Presence.part_of_day.to_s].presence || I18n.t("characters.around")
  def keepsake_name = I18n.t("keepsakes.#{keepsake}.name", default: KEEPSAKES.dig(keepsake, :name) || "Notebook")
  def keepsake_short = I18n.t("keepsakes.#{keepsake}.short", default: KEEPSAKES.dig(keepsake, :short) || "Notes")
  def keepsake_verb = I18n.t("keepsakes.#{keepsake}.verb", default: KEEPSAKES.dig(keepsake, :verb) || "noted")
  def portrait? = Rails.root.join("app/assets/images/portraits/#{slug}.svg").exist?

  # avatar drawn in CSS from the slug: stable, no image to host
  def avatar_tint = slug.sum % 8
  def avatar_motif = %w[stripes dots rings plain][slug.sum % 4]
end
