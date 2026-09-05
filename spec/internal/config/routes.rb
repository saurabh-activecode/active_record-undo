# frozen_string_literal: true

Rails.application.routes.draw do
  mount ActiveRecord::Undo::Engine => '/undo'
  root to: proc { [200, { 'Content-Type' => 'text/plain' }, ['Root OK']] }
  get '/dashboard', to: proc { [200, { 'Content-Type' => 'text/plain' }, ['Dashboard OK']] }, as: :dashboard
  get '/posts', to: proc { [200, { 'Content-Type' => 'text/plain' }, ['Posts OK']] }, as: :posts
end
