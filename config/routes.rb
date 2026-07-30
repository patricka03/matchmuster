Rails.application.routes.draw do
  devise_for :users

  resources :teams do
    resources :posts, only: %i[index create update destroy]

    resources :matches, only: %i[index show create update destroy] do
      resources :availabilities, only: %i[index create] do
        post :remind, on: :collection
      end

      resources :squad_selections, only: %i[index create update destroy]
    end

    resources :team_memberships, only: %i[index]
  end

  resources :availabilities, only: %i[update]

  resources :notifications, only: %i[index update destroy]

  resources :team_memberships, only: %i[create destroy] do
    member do
      patch :approve
      patch :reject
    end
  end
end
