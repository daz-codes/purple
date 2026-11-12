Rails.application.routes.draw do
  # Development only: the emails the app has "sent".
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

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
    resources :attempts, only: %i[ new create ], controller: "shift_attempts"
  end
  # Each move in a shift is its own resource. Messages are addressed by their opaque per-attempt ref.
  resources :shift_attempts, path: "attempts", param: :token, only: :show do
    scope module: :shift_attempts do
      resources :messages, param: :ref, only: [] do
        scope module: :messages do
          resource :reading, only: :create
          resource :headers, only: :create
          resource :verification, only: :create
          resource :report, only: :create
          resources :links, param: :key, only: [] do
            resource :visit, only: :create, module: :links
          end
          resources :attachments, param: :key, only: [] do
            resource :opening, only: :create, module: :attachments
          end
        end
      end
      # The page open in the in-game browser, and the moves you can make on it.
      resource :tab, only: :destroy do
        scope module: :tabs do
          resource :task_completion, only: :create
          resource :sign_in, only: :create
          resource :download_run, only: :create
        end
      end
      resource :wait, only: :create
      resource :completion, only: :create
    end
  end

  # Health check for load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
end
