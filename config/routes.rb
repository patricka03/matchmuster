Rails.application.routes.draw do
  devise_for :users
  resources :teams do
    resources :matches, only: [ :index, :show, :create, :update, :destroy ] do
      resources :availabilities, only: %i[index create]
    end
    resources :team_memberships, only: [ :index ]
  end

  resources :availabilities, only: %i[update]

resources :team_memberships, only: [ :create, :destroy ] do
  member do
    patch :approve
    patch :reject
  end
  end
end
