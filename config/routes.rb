Rails.application.routes.draw do

  devise_for :users, :controllers => { registrations: 'registrations' }

  resources :entries

  root 'welcome#index'

end
