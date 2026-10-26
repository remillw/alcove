# A verified webhook as received. Unique on (provider, event_id): that index is the "process once" guarantee.
class WebhookEvent < ApplicationRecord
end
