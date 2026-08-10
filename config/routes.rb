Rails.application.routes.draw do
  # devise_for :users
  devise_for :users, controllers: { registrations: "users/registrations", sessions: "users/sessions", passwords: "users/passwords"}
  get "users/me", to: "users#me"
  patch "/users/avatar", to: "users#update_avatar"
  patch "/users/profile", to: "users#update_profile"
  # patch "/users/change_password", to: "users#update_password"
  post "stripe/webhook", to: "stripe_webhooks#create"

  resources :teams do
    member do
      post :stripe_connect
      get :stripe_status
      post :stripe_dashboard
    end

    resources :posts, only: %i[index show create update destroy] do
      resources :post_reads, only: %i[index create]
    end

    resources :matches, only: %i[index show create update destroy] do
      resources :availabilities, only: %i[index create] do
        collection do
          get :mine
          post :remind
        end
      end

      resources :squad_selections, only: %i[index create update destroy]
      resources :match_payments, only: %i[index show create update destroy] do
        collection do
          get :summary
          post :bulk_create
        end

        member do
          post :checkout
        end
      end
    end

    resources :team_memberships,
              only: %i[index create]
  end

  resources :availabilities, only: %i[update]

  resources :notifications, only: %i[index update destroy]

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
