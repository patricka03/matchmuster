Rails.application.routes.draw do
  devise_for :users
  post "stripe/webhook", to: "stripe_webhooks#create"

  resources :teams do
    member do
      post :stripe_connect
      get :stripe_status
    end

    resources :posts, only: %i[index show create update destroy] do
      resources :post_reads, only: %i[index create]
    end

    resources :matches, only: %i[index show create update destroy] do
      resources :availabilities, only: %i[index create] do
        post :remind, on: :collection
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
    member do
      patch :approve
      patch :reject
    end
  end
end
