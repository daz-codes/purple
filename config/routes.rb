Rails.application.routes.draw do
  # Development only: the emails the app has "sent".
  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Authentication
  resource :session, only: %i[ new create destroy ]
  resource :registration, only: %i[ new create ]
  resources :passwords, param: :token, only: %i[ new create edit update ]
  resources :email_confirmations, param: :token, only: %i[ create show update ]

  # Leaderboards (tabs are params: side, period, relaxed) and public player profiles.
  resource :leaderboard, only: :show
  resources :profiles, path: "u", param: :display_name, only: :show

  # Which side the player prefers: asked once after signing up, and switchable from the dashboard.
  resource :side, only: %i[ new create ]

  # Your account page: your details and the devices you're signed in on.
  resource :account, only: :show
  namespace :account do
    resources :sessions, only: :destroy
    resource :other_sessions, only: :destroy
    # Relaxed mode and other per-player settings.
    resource :preferences, only: :update
  end

  # Red: the Workshop's targets, and the campaigns that attack them. Each move is its own resource.
  resources :targets, path: "workshop", only: %i[ index show ] do
    resources :campaigns, only: :create, controller: "red_campaigns"
  end
  resources :red_campaigns, path: "campaigns", param: :token, only: :show do
    scope module: :red_campaigns do
      resources :choices, param: :option_id, only: %i[ create destroy ]
      resource :launch, only: :create
    end
  end

  # Blue: paths of tracks of missions, and the attempts that play them.
  resources :paths, only: :index
  get "tracks", to: redirect("/paths")
  resources :tracks, only: :show
  resource :daily_intercept, path: "daily", only: :show
  get "shifts/:id", to: redirect("/missions/%{id}")
  resources :missions, only: :show do
    resources :attempts, only: %i[ new create ], controller: "mission_attempts"
  end
  # Each move in a mission is its own resource. Messages are addressed by their opaque per-attempt ref.
  resources :mission_attempts, path: "attempts", param: :token, only: :show do
    scope module: :mission_attempts do
      resources :messages, param: :ref, only: [] do
        scope module: :messages do
          resource :reading, only: :create
          resource :headers, only: :create
          resource :verification, only: :create
          resource :report, only: :create
          resource :archive, only: :create
          resource :reply, only: :create
          resources :flags, only: :create
          resources :notes, only: :create
          resource :details_share, only: :create
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
          resource :portal_submission, only: :create
          resource :sign_in, only: :create
          resource :download_run, only: :create
        end
      end
      # A signals mission's intercepts, also addressed by an opaque per-attempt ref.
      resources :intercepts, param: :ref, only: [] do
        scope module: :intercepts do
          resources :flags, only: :create
          resource :file, only: :show
        end
      end
      resources :hints, only: :create
      resource :stand_down, only: :create
    end
  end

  # Legal pages, linked from the footer and the sign-up form.
  get "privacy" => "pages#privacy"
  get "terms" => "pages#terms"

  # Health check for load balancers and uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
end
