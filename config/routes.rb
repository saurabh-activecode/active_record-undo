# frozen_string_literal: true

ActiveRecord::Undo::Engine.routes.draw do
  resources :logs, only: [] do
    member do
      post :restore
      get :status
    end
  end

  post '/restore/:token', to: 'restores#create', as: :signed_restore
  get '/status/:token', to: 'restores#status', as: :signed_status
end
