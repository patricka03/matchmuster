Rails.application.routes.draw do
  devise_for :users

  resources :teams do
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
