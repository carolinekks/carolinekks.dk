class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token

  def check
    render plain: "Access Denied", status: :ok
  end
end
