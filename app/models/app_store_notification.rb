# frozen_string_literal: true

# An App Store Server Notification (V2) that arrived, once per notificationUUID: Apple redelivers
# until it gets a 200, and a redelivery of one already processed does nothing.
class AppStoreNotification < ActiveRecord::Base
  validates :notification_uuid, presence: true
  validates :notification_type, presence: true
end
