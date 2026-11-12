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

  # Blue: tracks of shifts, and the attempts that play them.
  resources :tracks, only: %i[ index show ]
  resources :shifts, only: :show do
    resources :attempts, only: :create, controller: "shift_attempts"
  end
  resources :shift_attempts, path: "attempts", param: :token, only: :show do
    resources :actions, only: :create, controller: "shift_attempt_actions"
    resource :completion, only: :create, controller: "shift_attempt_completions"
  end

  # Health check for load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
end
