Rails.application.routes.draw do
  # Authentication
  resource :session, only: %i[ new create destroy ]
  resource :registration, only: %i[ new create ]
  resources :passwords, param: :token, only: %i[ new create edit update ]
  resources :email_confirmations, param: :token, only: %i[ create show update ]

  namespace :account do
    resources :sessions, only: %i[ index destroy ]
    resource :other_sessions, only: :destroy
  end

  # Health check for load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
end
