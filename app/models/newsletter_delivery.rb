# One row per person per newsletter: who was sent it, and which variant.
# The unique index on (user_id, newsletter) is what stops a second send.
class NewsletterDelivery < ActiveRecord::Base
  belongs_to :user
end
