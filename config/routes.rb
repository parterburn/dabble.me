Rails.application.routes.draw do

  devise_for :users, :controllers => { registrations: 'registrations' }

  get   '/entries/import' => 'entries#import', :as => "import_entries"
  match '/entries/import_process' => 'entries#process_import', via: [:put], :as => "import_process_entry"

  get '/entries/random' => 'entries#random', :as => "random_entry"
  
  match '/post' => 'entries#incoming', via: [:put]

  resources :entries

  root 'welcome#index'

  get '/privacy' => 'welcome#privacy'

end
