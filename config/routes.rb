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

  get "developer/launch_clubs",
      to: "developers/launch_clubs#index"

  patch "developer/launch_clubs/:id/grant",
        to: "developers/launch_clubs#grant"

  post "developer/app_updates",
       to: "developers/app_updates#create"

  get "developer/activities",
      to: "developers/activities#index"

  get "developer/activity",
      to: "developers/activity#index"

  namespace :developers,
            path: "developer" do
    resources :reports,
              only: %i[
                index
                show
                update
              ] do
      member do
        patch :remove_content
        patch :suspend_user
        patch :ban_user
        patch :restore_user
        patch :delete_user
      end
    end

    resources :users,
              only: %i[
                index
                destroy
              ] do
      member do
        patch :suspend
        patch :ban
        patch :restore
      end
    end
  end


  # ========================================
  # USERS
  # ========================================

  devise_for :users,
             controllers: {
               registrations: "users/registrations",
               sessions: "users/sessions",
               passwords: "users/passwords"
             }

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
  # SOCIAL SIGN-IN
  # ========================================

  post "auth/social",
       to: "social_auth#create"


  # ========================================
  # PUSH DEVICES
  # ========================================

  post "/push_devices",
       to: "push_devices#create"

  delete "/push_devices",
         to: "push_devices#destroy"

  # ========================================
  # STORE SUBSCRIPTION NOTIFICATIONS
  # ========================================

  post "subscriptions/google_play/notifications",
       to:
         "store_subscription_notifications#google_play"

  post "subscriptions/apple/notifications",
       to:
         "store_subscription_notifications#apple"

  # ========================================
  # STRIPE
  # ========================================

  post "stripe/webhook",
       to: "stripe_webhooks#create"


  # ========================================
  # TEAMS
  # ========================================

    resources :teams do
      get "subscription",
          to:
            "team_subscriptions#show"

      post "subscription/google_play/claim",
          to:
            "team_subscription_claims#google_play"

      post "subscription/apple/claim",
         to:
           "team_subscription_claims#apple"

      post "subscription/restore",
          to:
            "team_subscription_claims#restore"

      get "awards",

          to:
            "team_awards#show"

      # ========================================
      # CLUB FINANCE — PLUS
      # ========================================

      resource :finance,
               only: %i[show],
               controller: "team_finances"

      resources :finance_entries,
                only: %i[create update destroy],
                controller: "team_finance_entries"

      # ========================================
      # DIRECT MESSAGES
      # ========================================

      resources :conversations,
                only: %i[index show create] do
        collection do
          get :recipients
        end

        member do
          patch :read
        end

        resources :messages,
                  only: %i[index create]
      end

      # ========================================
      # MATCHDAY RUNNING LATE
      # ========================================

      get "matchday/late_statuses",
          to: "match_late_statuses#matchday"

      member do
        post :stripe_connect
        get :stripe_status
        post :stripe_dashboard

        patch :badge,
              action: :update_badge
      end

      resources :posts,
                only: %i[
                  index
                  show
                  create
                  update
                  destroy
                ] do
        resources :post_reads,
                  only: %i[
                    index
                    create
                  ]
      end


      # ========================================
      # TRAINING
      # ========================================

      resources :trainings,
                only: %i[
                  index
                  show
                  create
                  update
                  destroy
                ] do
        collection do
          post :recurring,
               action:
                 :create_recurring
        end

        resources :training_availabilities,
                  only: %i[
                    index
                    create
                    update
                  ] do
          collection do
            get :mine
          end
        end
      end


      # ========================================
      # MATCHES
      # ========================================

      resources :matches,
                only: %i[
                  index
                  show
                  create
                  update
                  destroy
                ] do
        get "late_statuses",
            to: "match_late_statuses#index"

        # MATCHMUSTER_RUNNING_LATE_COMPAT_V3
        put "late_status",
            to: "match_late_statuses#upsert"

        post "late_status",
             to: "match_late_statuses#upsert"

        patch "late_status",
              to: "match_late_statuses#upsert"

        post "late_statuses",
             to: "match_late_statuses#upsert"

        put "late_statuses",
            to: "match_late_statuses#upsert"

        patch "late_statuses",
              to: "match_late_statuses#upsert"

        delete "late_status",
               to: "match_late_statuses#destroy"

        resources :match_player_stats,
                  only: %i[
                    index
                    create
                  ]


        # ----------------------------------------
        # AVAILABILITIES
        # ----------------------------------------

        resources :availabilities,
                  only: %i[
                    index
                    create
                  ] do
          collection do
            get :mine
            post :remind
          end
        end


        # ----------------------------------------
        # MATCH RATINGS
        # ----------------------------------------

        resources :match_ratings,
                  only: %i[
                    create
                  ]

        get "rating_status",
            to: "match_ratings#status"

        get "rating_results",
            to: "match_ratings#results"


        # ----------------------------------------
        # SQUAD SELECTIONS
        # ----------------------------------------

        resources :squad_selections,
                  only: %i[
                    index
                    create
                    update
                    destroy
                  ] do
          collection do
            post :not_selected
          end
        end


        # ----------------------------------------
        # MATCH PAYMENTS
        # ----------------------------------------

        resources :match_payments,
                  only: %i[
                    index
                    show
                    create
                    update
                    destroy
                  ] do
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

      resources :team_memberships,
                only: %i[
                  index
                  create
                ]
    end


  # ========================================
  # AVAILABILITY UPDATE
  # ========================================

  resources :availabilities,
            only: %i[
              update
            ]


  # ========================================
  # REPORTING AND BLOCKING
  # ========================================

  resources :reports,
            only: %i[
              create
            ]

  resources :user_blocks,
            only: %i[
              index
              create
              destroy
            ]


  # ========================================
  # NOTIFICATIONS
  # ========================================

  resources :notifications,
            only: %i[
              index
              update
              destroy
            ] do
    collection do
      patch :mark_all_read
    end
  end


  # ========================================
  # TEAM MEMBERSHIP ACTIONS
  # ========================================

  resources :team_memberships,
            only: %i[
              destroy
            ] do
    collection do
      post :join
    end

    member do
      patch :approve
      patch :reject
    end
  end
end
