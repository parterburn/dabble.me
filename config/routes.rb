Rails.application.routes.draw do
  authenticate :user, ->(u) { u.is_admin? } do
    resources :inspirations
    resources :payments
    get 'admin/users' => 'admin#users', as: 'admin_users'
    get 'admin/stats' => 'admin#stats', as: 'admin_stats'
    get 'admin/photos' => 'admin#photos', as: 'admin_photos'
  end

  devise_for :users, controllers: { registrations: 'registrations' }

  devise_scope :user do
    get 'settings/(:user_key)'     => 'registrations#settings', as: 'settings'
    match 'unsubscribe/:user_key'  => 'registrations#unsubscribe', as: 'unsubscribe', via: [:put]
  end

  get 'entries/import'   => 'import#show', as: 'import'
  match 'entries/import' => 'import#update', via: [:put], as: 'import_process'
  match '/entries/import/ohlife/upload'  => 'import#process_ohlife_images', via: [:post], :as => 'import_ohlife_images'
  get 'entries/export'   => 'entries#export', as: 'export_entries'
  get 'entries/calendar' => 'entries#calendar', as: 'entries_calendar'

  resources :entries
  get 'past/random',               to: 'entries#random', as: 'random_entry'
  get 'past',                      to: redirect('/past/all'), as: 'past_entries'
  get 'past/(:group)(/:subgroup)', to: 'entries#index',  as: 'group_entries'
  get 'latest',                    to: 'entries#latest', as: 'latest_entry'  
  get 'review',                    to: 'entries#review', as: 'review'
  get 'search',                    to: 'searches#show'
  get 'write',                     to: redirect('/entries/new')
  get 'privacy',                   to: 'welcome#privacy'
  get 'faqs',                      to: 'welcome#faqs'
  get 'subscribe',                 to: 'welcome#subscribe'
  get 'donate',                    to: redirect('/subscribe')
  get 'pro',                       to: redirect('/subscribe')
  match 'payment_notify',          to: 'payments#payment_notify', via: [:post]
  get 'ohlife-alternative',        to: 'welcome#ohlife_alternative'
  post 'email_processor',          to: 'griddler/emails#create'

  get '/cast(/*path)', to: redirect('https://vidcast.dabble.me') # temporary for old content

  root 'welcome#index'  
end
