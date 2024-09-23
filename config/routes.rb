Rails.application.routes.draw do
  authenticate :user, ->(u) { u.admin? } do
    resources :inspirations, path: '/admin/inspirations'
    resources :payments, path: '/admin/payments'
    get 'admin/users' => 'admin#users', as: 'admin_users'
    get 'admin/stats' => 'admin#stats', as: 'admin_stats'
    get 'admin/photos' => 'admin#photos', as: 'admin_photos'
  end

  devise_for :users, controllers: { registrations: 'registrations', session: 'sessions', passwords: 'passwords' }

  devise_scope :user do
    post "/validate_otp", to: "sessions#validate_otp", as: "validate_otp"
  end

  devise_scope :user do
    get 'settings/(:user_key)'     => 'registrations#settings', as: 'settings'
    get 'security'                 => 'registrations#security', as: 'security'
    match 'unsubscribe/:user_key'  => 'registrations#unsubscribe', as: 'unsubscribe', via: [:put]
  end

  get 'entries/import/(:type)'   => 'import#show', as: 'import'
  match 'entries/import/(:type)' => 'import#update', via: [:put], as: 'import_process'
  match '/entries/import/ohlife/upload'  => 'import#process_ohlife_images', via: [:post], :as => 'import_ohlife_images'
  get 'entries/export'   => 'entries#export', as: 'export_entries'
  get 'entries/calendar' => 'entries#calendar', as: 'entries_calendar'

  get 'past(/:anything)',               to: redirect('/entries')
  get 'entries/emotion/:emotion',       to: 'entries#index', as: 'entries_emotion'
  get 'entries/songs',                  to: 'entries#spotify', as: 'spotify'
  get 'entries/random',                 to: 'entries#random', as: 'random_entry'
  get 'entries/:year/:month/:day',      to: 'entries#show',  as: 'day_entry'
  post 'entries/:id/process_ai',        to: 'entries#process_as_ai',  as: 'process_as_ai'
  match 'entries/:id/respond_to_ai' => 'entries#respond_to_ai', as: 'respond_to_ai', via: [:put]
  resources :entries, except: [:show]
  get 'entries/(:group)(/:subgroup)',   to: 'entries#index',  as: 'group_entries'
  get 'latest',                         to: 'entries#latest', as: 'latest_entry'
  get 'review/(:year)',                 to: 'entries#review', as: 'review'
  get 'play',                           to: redirect('/entries/songs')
  get 'search',                         to: 'searches#show'
  get 'write',                          to: redirect('/entries/new')
  get 'privacy',                        to: 'welcome#privacy'
  get 'terms',                          to: 'welcome#terms'
  get 'features',                       to: 'welcome#features'
  get 'faqs',                           to: 'welcome#faqs'
  get 'subscribe',                      to: 'welcome#subscribe'
  get 'donate',                         to: redirect('/subscribe')
  get 'pro',                            to: redirect('/subscribe')
  match 'payment_notify',               to: 'payments#payment_notify', via: [:post]
  get 'ohlife-alternative',             to: 'welcome#ohlife_alternative'
  post 'email_processor',               to: 'griddler/emails#create'
  post 'email_events',                  to: 'email_events#create'

  post "checkout", to: "payments#checkout", as: "checkout"
  get "success", to: "payments#success"
  get "billing", to: "payments#billing", as: "billing"
  mount StripeEvent::Engine, at: "/stripe_events"
  get '/health_check', to: proc { [200, {}, ['success']] }

  root 'welcome#index'

  # get "*any", via: :all, to: "errors#not_found"
end
