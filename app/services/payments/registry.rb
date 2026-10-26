# Name -> adapter class (by name, so nothing loads until it is used). The active one is chosen by PAYMENTS_PROVIDER.
module Payments
  module Registry
    PROVIDERS = {
      "sandbox" => "Payments::Providers::Sandbox",
      "stripe" => "Payments::Providers::Stripe"
    }

    def self.register(name, class_name) = PROVIDERS[name.to_s] = class_name

    def self.fetch(name)
      klass = PROVIDERS.fetch(name.to_s) { raise UnknownProvider, "unknown payment provider #{name.inspect}" }.constantize
      raise ProviderUnavailable, "#{name} is not configured" unless klass.enabled?
      klass.new
    end
  end
end
