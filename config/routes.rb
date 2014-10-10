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
  
  get '/entries/random' => 'entries#random', :as => "random_entry"

  get '/entries/new' => 'entries#new', :as => "new_entry"
  get '/entries/edit(/:id)' => 'entries#edit', :as => "edit_entry"
  get '/entries/(:group)(/:subgroup)' => 'entries#index', :as => "group_entries"
  resources :entries
  resources :inspirations

  root 'welcome#index'

  get '/admin' => 'application#admin', :as => "admin"
  
  get '/settings', to: redirect('/users/edit')
  get '/write', to: redirect('/entries/new')
  get '/past', to: redirect('/entries')
  get '/privacy' => 'welcome#privacy'
  get '/faqs'     => 'welcome#faqs'
  get '/donate'  => 'welcome#donate'
  get '/ohlife-alternative'  => 'welcome#ohlife_alternative'
  
  post '/email_processor' => 'griddler/emails#create'

end
