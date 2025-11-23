Rails.application.routes.draw do
  root "home#main"
  get "up" => "rails/health#show", as: :rails_health_check
  get "/changelog_data", to: "changelog#index"
  get "/2c085e5c6556b7a9", to: proc { [ 200, { "Content-Type" => "text/plain" }, [ "Access Denied" ] ] }
  post "changelog_webhook", to: "changelog#webhook"
end
