Rails.application.routes.draw do
  devise_for :developers,
             path: "developer",
             path_names: {
               sign_in: "login",
               sign_out: "logout"
             },
             controllers: {
               sessions: "developers/sessions"
             },
             skip: [:registrations],
             defaults: {
               format: :json
             }

  get "developer/dashboard",
      to: "developers/dashboard#show"

  get "developer/managers",
      to: "developers/managers#index"

  patch "developer/managers/:id/approve",
        to: "developers/managers#approve"

  patch "developer/managers/:id/reject",
        to: "developers/managers#reject"

  post "developer/app_updates",
       to: "developers/app_updates#create"

  get "developer/activities",
      to: "developers/activities#index"

  get "developer/activity",
      to: "developers/activity#index"


  # ========================================
  # USERS
  # ========================================

  devise_for :users, controllers: { registrations: "users/registrations", sessions: "users/sessions", passwords: "users/passwords" }

  get "users/me",
      to: "users#me"

  patch "/users/avatar",
        to: "users#update_avatar"

  patch "/users/profile",
        to: "users#update_profile"

  patch "/users/preferred_position",
        to: "team_memberships#update_preferred_position"

  patch "/users/change_password",
        to: "users#update_password"

  delete "/users/account",
         to: "users#destroy_account"


  # ========================================
  # STRIPE
  # ========================================

  post "stripe/webhook",
       to: "stripe_webhooks#create"


  # ========================================
  # TEAMS
  # ========================================

  resources :teams do
    get "awards", to: "team_awards#show"

    member do
      post :stripe_connect
      get :stripe_status
      post :stripe_dashboard

      patch :badge,
            action: :update_badge
    end

    resources :posts, only: %i[ index show create update destroy ] do

      resources :post_reads, only: %i[ index create ]
    end


    # ========================================
    # MATCHES
    # ========================================

    resources :matches, only: %i[index show create update destroy ] do

      resources :match_player_stats, only: %i[index create]

      # ----------------------------------------
      # AVAILABILITIES
      # ----------------------------------------

      resources :availabilities, only: %i[ index create ] do

        collection do
          get :mine
          post :remind
        end
      end


      # ----------------------------------------
      # MATCH RATINGS
      # ----------------------------------------

      resources :match_ratings, only: %i[ create ]
      get "rating_status", to: "match_ratings#status"

      get "rating_results", to: "match_ratings#results"

      get "rating_status", to: "match_ratings#status"


      # ----------------------------------------
      # SQUAD SELECTIONS
      # ----------------------------------------

      resources :squad_selections,
                only: %i[ index create update destroy ]


      # ----------------------------------------
      # MATCH PAYMENTS
      # ----------------------------------------

      resources :match_payments,
                only: %i[ index show create update destroy ] do

        collection do
          get :summary
          post :bulk_create
        end

        member do
          post :checkout
        end
      end
    end


    # ========================================
    # TEAM MEMBERSHIPS
    # ========================================

    resources :team_memberships, only: %i[ index create ]
  end


  # ========================================
  # AVAILABILITY UPDATE
  # ========================================

  resources :availabilities, only: %i[ update ]


  # ========================================
  # NOTIFICATIONS
  # ========================================

  resources :notifications, only: %i[ index update destroy]


  # ========================================
  # TEAM MEMBERSHIP ACTIONS
  # ========================================

  resources :team_memberships, only: %i[destroy] do

    collection do
      post :join
    end

    member do
      patch :approve
      patch :reject
    end
  end
end
