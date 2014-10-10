require 'sidekiq/web'

Rails.application.routes.draw do

  #constraints(:host => /localhost/) do
    mount Sidekiq::Web => '/sidekiq'
  #end

  devise_for :users, :controllers => { registrations: 'registrations' }

  get   '/entries/import/ohlife' => 'import#import_ohlife', :as => "import_ohlife"
  match '/entries/import/ohlife/process' => 'import#process_ohlife', via: [:put], :as => "import_ohlife_process"
  match '/entries/import/ohlife/upload' => 'import#process_ohlife_images', via: [:post], :as => "import_ohlife_images"  
  get   '/entries/export' => 'entries#export', :as => "export_entries"

  resources :entries
  resources :inspirations

  get '/past/random'               => 'entries#random', :as => "random_entry"
  get '/past'                      => "entries#index",  :as => "past_entries"  
  get '/past/(:group)(/:subgroup)' => 'entries#index',  :as => "group_entries"  

  root 'welcome#index'

  get '/admin' => 'application#admin', :as => "admin"
  
  get '/settings', to: redirect('/users/edit')
  get '/write', to: redirect('/entries/new')
  get '/privacy' => 'welcome#privacy'
  get '/faqs'     => 'welcome#faqs'
  get '/donate'  => 'welcome#donate'
  get '/ohlife-alternative'  => 'welcome#ohlife_alternative'
  
  post '/email_processor' => 'griddler/emails#create'

end
