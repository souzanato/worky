Rails.application.routes.draw do
  localized do
    devise_for :users, path_prefix: I18n.t("routes.auth"), path: I18n.t("routes.devise_user"), controllers: {
      sessions: "auth/sessions",
      registrations: "auth/registrations",
      passwords: "auth/passwords",
      confirmations: "auth/confirmations",
      unlocks: "auth/unlocks"
    }
    resources :users
    resources :workflows do
      resources :ai_collect_configs
      resources :steps, only: [ :new, :create, :edit, :update, :destroy ] do
        member do
          patch :move_up
          patch :move_down
        end
        resources :actions, only: [ :new, :create, :edit, :update, :destroy ] do
          member do
            patch :move_up
            patch :move_down
          end
        end
      end
      resources :artifacts, only: [ :new, :create, :edit, :update, :destroy ]
    end

    post "/workflow_executions/:workflow_execution_id/actions/:action_id/prompt_generators", to: "prompt_generators#create", as: :action_prompt_generators

    resources :clients do
        resources :artifacts, only: [ :new, :create, :edit, :update, :destroy ]
        resources :workflow_executions, only: [ :index, :new, :create, :show, :update, :destroy ] do
          resources :workflow_execution_events, only: [ :create ] do
            collection do
              post :stream
            end
          end
        end
    end

    resources :workflow_executions, only: [] do
      resources :ai_records
      resources :artifacts do
        member do
          get :download
        end
      end
    end

    namespace :api do
      namespace :v1 do
        resources :web_scrapings, only: [ :show, :create ]

        # PDF Processing
        resources :pdfs, only: [] do
          collection do
            get :health
            post :extract_full
            post :extract_text
            post :extract_images
            post :extract_annotations
            post :extract_bookmarks
            post :extract_links
            post :render_page
            post :render_page_base64
            post :render_with_annotations
            post :render_annotations_images
            post :render_pdf_images
          end
        end
      end
    end
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  # get "up": "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest": "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker": "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  mount ActionCable.server => "/cable"

  root "home#index"
end
