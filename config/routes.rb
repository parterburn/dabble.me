Rails.application.routes.draw do

  devise_for :users, :controllers => { registrations: 'registrations' }

  get   '/entries/import' => 'entries#import', :as => "import_entries"
  match '/entries/import_process' => 'entries#process_import', via: [:put], :as => "import_process_entry"

  resources :entries
  get   '/entries(/:year)(/:month)' => 'entries#index'  

  root 'welcome#index'

end
