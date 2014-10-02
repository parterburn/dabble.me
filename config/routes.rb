require 'sidekiq/web'

Rails.application.routes.draw do

  constraints(:host => /localhost/) do
    mount Sidekiq::Web => '/sidekiq'
  end

  devise_for :users, :controllers => { registrations: 'registrations' }

  get   '/entries/import' => 'entries#import', :as => "import_entries"
  match '/entries/import_process' => 'entries#process_import', via: [:put], :as => "import_process_entry"

  get '/entries/random' => 'entries#random', :as => "random_entry"

  resources :entries

  get   '/export' => 'entries#export', :as => "export_entries"

  root 'welcome#index'

  get '/privacy' => 'welcome#privacy'
  
  post '/email_processor' => 'griddler/emails#create'

end
