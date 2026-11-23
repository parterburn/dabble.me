# frozen_string_literal: true

# A connected app a user was emailed about for going a year unused (StaleConnectedAppsWorker),
# and the last use that email named.
class StaleAppNotice < ActiveRecord::Base
  belongs_to :user
  belongs_to :oauth_application, class_name: 'Doorkeeper::Application'
end
