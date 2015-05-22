require 'sidekiq/web'

Rails.application.routes.draw do

  authenticate :user, lambda { |u| u.is_admin? } do
    mount Sidekiq::Web => '/sidekiq'
  end  

  devise_for :users, :controllers => { registrations: 'registrations' }

  devise_scope :user do
    get '/settings/(:user_key)'       => 'registrations#settings', :as => "settings"
    match '/unsubscribe/:user_key'  => 'registrations#unsubscribe', :as => "unsubscribe", via: [:put]
  end

  get   '/entries/import/ohlife'         => 'import#import_ohlife', :as => "import_ohlife"
  match '/entries/import/ohlife/process' => 'import#process_ohlife', via: [:put], :as => "import_ohlife_process"
  match '/entries/import/ohlife/upload'  => 'import#process_ohlife_images', via: [:post], :as => "import_ohlife_images"  
  get   '/entries/export'                => 'entries#export', :as => "export_entries"
  get   '/entries/calendar'              => 'entries#calendar', :as => "entries_calendar"

  resources :entries
  resources :inspirations
  resources :donations

  get '/past/random'               => 'entries#random', :as => "random_entry"
  get '/past'                      => "entries#index",  :as => "past_entries"  
  get '/past/(:group)(/:subgroup)' => 'entries#index',  :as => "group_entries"  
  get "/search", to: "searches#show"
  
  root 'welcome#index'

  get '/admin'                  => 'application#admin', :as => "admin"
  
  get '/write',                 to: redirect('/entries/new')
  get '/privacy'                => 'welcome#privacy'
  get '/faqs'                   => 'welcome#faqs'
  get '/subscribe'              => 'welcome#donate'
  get '/donate',                to: redirect('/subscribe')
  get '/pro',                   to: redirect('/subscribe')
  match '/payment_notify'       => 'donations#payment_notify', via: [:post]
  get '/ohlife-alternative'     => 'welcome#ohlife_alternative'
  
  post '/email_processor'       => 'griddler/emails#create'

end
