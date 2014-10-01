Rails.application.routes.draw do

  devise_for :users, :controllers => { registrations: 'registrations' }

  get   '/entries/import' => 'entries#import', :as => "import_entries"
  match '/entries/import_process' => 'entries#process_import', via: [:put], :as => "import_process_entry"

  get '/entries/random' => 'entries#random', :as => "random_entry"

  resources :entries

  get   '/post_sendgrid' => 'welcome#index'
  match '/post_sendgrid' => 'entries#incoming_sendgrid', via: [:post]

  get   '/post_mandrill' => 'welcome#index'
  match '/post_mandrill' => 'entries#incoming_mandrill', via: [:post]  

  get   '/export' => 'entries#export', :as => "export_entries"

  root 'welcome#index'

  get '/privacy' => 'welcome#privacy'

end
