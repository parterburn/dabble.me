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

  resources :entries
  resources :inspirations


  root 'welcome#index'

  get '/admin' => 'application#admin', :as => "admin"

  get '/privacy' => 'welcome#privacy'
  
  post '/email_processor' => 'griddler/emails#create'

end
