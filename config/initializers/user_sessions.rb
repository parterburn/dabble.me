# Ties each signed-in browser to a UserSession row, so it shows in the Sessions list and can be
# signed out on its own (WebSessions has the details). Devise's own hooks are left as they are.
# WebSessions is looked up when a hook runs, so code reloading in development still works.
Warden::Manager.after_set_user except: :fetch do |user, warden, options|
  WebSessions.signed_in(user, warden, options)
end

Warden::Manager.after_set_user only: :fetch do |user, warden, options|
  WebSessions.fetched(user, warden, options)
end

Warden::Manager.before_logout do |user, warden, options|
  WebSessions.signing_out(user, warden, options)
end
