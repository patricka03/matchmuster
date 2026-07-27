Rails.application.routes.draw do
  devise_for :users
  resources :teams do
  resources :team_memberships, only: [:index]
  end

resources :team_memberships, only: [:create, :destroy] do
  member do
    patch :approve
    patch :reject
  end
  end
end
