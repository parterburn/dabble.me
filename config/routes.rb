Rails.application.routes.draw do

  devise_for :users, :controllers => { registrations: 'registrations' }

  get   '/entries/import' => 'entries#import', :as => "import_entries"
  match '/entries/import_process' => 'entries#process_import', via: [:put], :as => "import_process_entry"

  get '/entries/random' => 'entries#random', :as => "random_entry"

  resources :entries

  get   '/post' => 'welcome#index'
  match '/post' => 'entries#incoming', via: [:post]

  root 'welcome#index'

  get '/privacy' => 'welcome#privacy'

end
