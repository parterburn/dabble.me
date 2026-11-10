require "sidekiq/web"
require "sidekiq/cron/web"
Rails.application.routes.draw do
  use_doorkeeper do
    controllers(
      authorizations: "oauth/authorizations",
      authorized_applications: "oauth/authorized_applications"
    )
  end

  # Font Awesome Slab icons, proxied from S3 so CSS masks stay same-origin.
  get 'icons/slab/:name', to: 'icons#show', as: :slab_icon, constraints: { name: /[a-z0-9-]+/, format: 'svg' }

  get '.well-known/oauth-protected-resource', to: 'oauth/metadata#protected_resource'
  get '.well-known/oauth-protected-resource/mcp', to: 'oauth/metadata#protected_resource'
  get '.well-known/oauth-authorization-server', to: 'oauth/metadata#authorization_server'
  get '.well-known/oauth-authorization-server/mcp', to: 'oauth/metadata#authorization_server'
  get '.well-known/webmcp', to: 'mcp/discovery#webmcp', format: false
  get '.well-known/webmcp.json', to: redirect(status: 301) { |_params, req|
    "#{req.protocol}#{req.host_with_port}/.well-known/webmcp"
  }, format: false
  get '.well-known/ai-catalog.json', to: 'mcp/discovery#ai_catalog', format: false
  get '.well-known/api-catalog', to: 'mcp/discovery#api_catalog'
  get '.well-known/mcp.json', to: 'mcp/discovery#server_card', format: false
  get '.well-known/agents.md', to: 'mcp/discovery#agents', format: false
  get 'mcp/server-card', to: 'mcp/discovery#server_card'
  match 'webmcp/tools/:name', to: 'mcp/discovery#invoke_tool', via: %i[get post options], constraints: { name: /[a-z0-9_]+/ }
  scope path: 'webmcp/journal', module: 'webmcp', as: :webmcp_journal do
    match 'session', to: 'journal#session_info', via: %i[get post]
    post 'search', to: 'journal#search'
    post 'list', to: 'journal#list'
    post 'analyze', to: 'journal#analyze'
  end

  namespace :oauth, defaults: { format: :json } do
    resources :registrations, only: :create
  end

  # iOS app API (see MobileApp, Api::V1::BaseController).
  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      get 'me', to: 'me#show'
      get 'today', to: 'today#show'
      get 'prompts', to: 'prompts#index'
      resources :entries, only: %i[index show create update destroy] do
        collection do
          get :random
          get :on_this_day
          get :months
          get :days
          get :memory_days
        end
      end
      get 'search', to: 'searches#show'
      get 'stats', to: 'stats#show'
      get 'hashtags', to: 'hashtags#index'
      resource :email_schedule, only: %i[show update]
      resources :dated_hashtags, only: %i[index create update destroy]
      resources :image_uploads, only: :create
      post 'account/deletion_request', to: 'accounts#deletion_request'
    end
  end

  authenticate :user, ->(u) { u.admin? } do
    resources :inspirations, path: '/admin/inspirations'
    resources :payments, path: '/admin/payments'
    get 'admin/users' => 'admin#users', as: 'admin_users'
    get 'admin/users/:id/edit' => 'admin#edit_user', as: 'edit_admin_user'
    patch 'admin/users/:id' => 'admin#update_user', as: 'admin_user'
    post 'admin/users/:id/password_reset' => 'admin#send_password_reset', as: 'admin_user_password_reset'
    post 'admin/users/:id/ignored_email_images' => 'admin#create_ignored_email_image', as: 'admin_user_ignored_email_images'
    delete 'admin/users/:id/ignored_email_images/:ignored_email_image_id' => 'admin#destroy_ignored_email_image', as: 'admin_user_ignored_email_image'
    get 'admin/stats' => 'admin#stats', as: 'admin_stats'
    post 'admin/stats/capture' => 'admin#capture_stats', as: 'capture_admin_stats'
    get 'admin/photos' => 'admin#photos', as: 'admin_photos'
    get 'email_replies_test', to: 'entries#email_replies_test'
    mount Sidekiq::Web => "/sidekiq"
  end

  devise_for :users, controllers: { registrations: 'registrations', sessions: 'sessions', passwords: 'passwords' }
  get '/users/:id', to: redirect('/security'), as: 'user'

  devise_scope :user do
    post "/validate_otp", to: "sessions#validate_otp", as: "validate_otp"
  end

  namespace :passkeys do
    resources :registrations, only: [:new, :create, :destroy]
    resources :sessions, only: [:new, :create]
  end

  devise_scope :user do
    get 'settings/mcp', to: redirect { |_params, req| "#{req.protocol}#{req.host_with_port}/mcp-server" }
    get 'settings/delete-account'  => 'registrations#delete_account', as: 'delete_account'
    # Before settings/(:user_key), which would otherwise match this path.
    get 'settings/posting-address' => 'registrations#posting_address', as: 'posting_address'
    post 'settings/posting-address/reset' => 'registrations#reset_posting_address', as: 'reset_posting_address'
    # Emails link to settings?token=<signed token>. Older emails put the
    # posting address in the path; those keep working until the user resets it.
    get 'settings/(:user_key)'     => 'registrations#settings', as: 'settings'
    get 'security'                 => 'registrations#security', as: 'security'
    match 'unsubscribe(/:user_key)' => 'registrations#unsubscribe', as: 'unsubscribe', via: [:put]
  end

  get 'entries/import/(:type)'   => 'import#show', as: 'import'
  match 'entries/import/(:type)' => 'import#update', via: [:put], as: 'import_process'
  match '/entries/import/ohlife/upload'  => 'import#process_ohlife_images', via: [:post], :as => 'import_ohlife_images'
  get 'entries/export'   => 'entries#export', as: 'export_entries'
  get 'entries/calendar' => 'entries#calendar', as: 'entries_calendar'

  get 'past(/:anything)',               to: redirect('/entries')
  get 'entries/emotion(/:anything)',    to: redirect('/entries') # sentiment tags were removed
  get 'entries/ai',                     to: redirect('/entries') # stored AI replies were removed
  get 'entries/songs',                  to: 'entries#spotify', as: 'spotify'
  get 'entries/random',                 to: 'entries#random', as: 'random_entry'
  get 'entries/:year/:month/:day',      to: 'entries#show',  as: 'day_entry'
  post 'entries/:id/reflection',        to: 'entries#reflection', as: 'entry_reflection'
  match 'entries/:id/image_error'   => 'entries#dismiss_image_error', as: 'dismiss_entry_image_error', via: [:delete]
  resources :entries, except: [:show]
  get 'entries/(:group)(/:subgroup)',   to: 'entries#index',  as: 'group_entries'
  get 'latest',                         to: 'entries#latest', as: 'latest_entry'
  get 'rewind/(:year)',                 to: 'entries#review', as: 'rewind'
  get 'review(/:year)',                 to: redirect { |params, _| ["/rewind", params[:year].to_s[/\A\d{4}\z/]].compact.join("/") }
  get 'play',                           to: redirect('/entries/songs')
  get 'search',                         to: 'searches#show'
  get 'write',                          to: redirect('/entries/new')
  get 'privacy',                        to: 'welcome#privacy'
  get 'terms',                          to: 'welcome#terms'
  get 'support',                        to: 'welcome#support'
  get 'mcp-server',                     to: 'welcome#mcp_server', as: :mcp_server_docs
  get 'mcp-server/developers',          to: 'welcome#mcp_server_developers', as: :mcp_server_developer_docs
  get 'dabble-me-vs-day-one-ai-journaling', to: 'welcome#day_one_ai_journaling', as: :day_one_ai_journaling
  get 'day-one-alternative',            to: 'welcome#day_one_alternative', as: :day_one_alternative
  get 'best-journaling-apps-with-mcp',  to: 'welcome#best_journaling_apps_with_mcp', as: :best_journaling_apps_with_mcp
  match 'mcp', to: 'mcp#invoke', via: %i[get post], format: :json, as: :mcp

  # Redirects for old routes
  get 'features',                       to: redirect('/#features')
  get 'faqs',                           to: redirect('/support')
  get 'pricing',                        to: redirect('/#pricing')
  get 'subscribe',                      to: "welcome#subscribe"
  get 'pro',                            to: redirect('/subscribe')
  get 'pay',                            to: redirect { ENV['PAYMENT_LINK'] }
  get 'pay/:amount',                    to: redirect { |params, _req|
    "#{ENV['PAYMENT_LINK']}?prefilled_amount=#{params[:amount].to_i * 100}"
  }, constraints: { amount: /\d+/ }
  match 'payment_notify',               to: 'payments#payment_notify', via: [:post]
  get 'ohlife-alternative',             to: 'welcome#ohlife_alternative'
  post 'email_processor',               to: 'inbound_emails#create'
  post 'email_events',                  to: 'email_events#create'

  post "checkout", to: "payments#checkout", as: "checkout"
  get "success", to: "payments#success"
  get "billing", to: "payments#billing", as: "billing"
  mount StripeEvent::Engine, at: "/stripe_events"
  get '/health_check', to: proc { [200, {}, ['success']] }

  root 'welcome#index'

  match '/404', to: 'errors#not_found', via: :all
  match '/422', to: 'errors#unprocessable_entity', via: :all
  match '/500', to: 'errors#internal_server_error', via: :all
  match '/504', to: 'errors#timeout', via: :all

  get "/sw.js", to: "application#service_worker", as: :service_worker
end
