Rails.application.routes.draw do
  root "characters#index"

  resources :characters, only: %i[index show] do
    post :conversation, on: :member, to: "conversations#create"
  end
  resources :conversations, only: %i[index show destroy] do
    resources :messages, only: :create
  end
  resources :messages, only: [] do
    member do
      patch :cancel
      post :report
    end
  end
  resources :memories, only: :destroy

  resource :session, only: %i[new create destroy]
  resource :registration, only: %i[new create]
  resource :account, only: %i[show destroy] do
    get :export
  end

  get "legal" => "pages#legal"
  get "terms" => "pages#terms"
  get "privacy" => "pages#privacy"

  get "up" => "rails/health#show", as: :rails_health_check
end
