Rails.application.routes.draw do
  authenticate :user, ->(u) { u.is_admin? } do
    resources :inspirations
    resources :payments
    get 'admin' => 'admin#metrics', as: 'admin'
    get 'admin/users' => 'admin#users', as: 'admin_users'
    get 'admin/stats' => 'admin#stats', as: 'stats'
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
  get 'past/random'               => 'entries#random', as: 'random_entry'
  get 'past'                      => 'entries#index',  as: 'past_entries'
  get 'past/(:group)(/:subgroup)' => 'entries#index',  as: 'group_entries'
  get 'review/:year'              => 'entries#review', as: 'review'
  get 'search', to: 'searches#show'
  root 'welcome#index'
  get 'write',                 to: redirect('/entries/new')
  get 'privacy'                => 'welcome#privacy'
  get 'faqs'                   => 'welcome#faqs'
  get 'subscribe'              => 'welcome#subscribe'
  get 'donate',                to: redirect('/subscribe')
  get 'pro',                   to: redirect('/subscribe')
  match 'payment_notify'       => 'payments#payment_notify', via: [:post]
  get 'ohlife-alternative'     => 'welcome#ohlife_alternative'
  post 'email_processor'       => 'griddler/emails#create'

  get '/cast(/*path)', to: redirect('https://vidcast.dabble.me')
end
