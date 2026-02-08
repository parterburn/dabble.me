class ErrorsController < ApplicationController
  layout 'marketing'
  skip_before_action :verify_authenticity_token

  def not_found
    respond_to do |format|
      format.html { render status: 404 }
      format.all { render status: 404, body: nil }
    end
  rescue ActionController::UnknownFormat
    render status: 404, plain: "This page does not exist. Looking for VidCast? It moved to https://vidcast.dabble.me/."
  end

  def internal_server_error
    respond_to do |format|
      format.html { render status: 500 }
      format.all { render status: 500, body: nil }
    end
  end

  def timeout
    respond_to do |format|
      format.html { render status: 504 }
      format.all { render status: 504, body: nil }
    end
  end

  def unprocessable_entity
    respond_to do |format|
      format.html { render status: 422 }
      format.all { render status: 422, body: nil }
    end
  end
end
