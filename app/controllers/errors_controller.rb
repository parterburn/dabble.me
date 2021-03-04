class ErrorsController < ApplicationController
  # отделять строки бы, а то сливается всё

  skip_before_action :verify_authenticity_token, only: :not_found

  def not_found
    respond_to do |format|
      format.html { render status: 404 }
    end
  rescue ActionController::UnknownFormat
    render status: 404, text: "This page does not exist. Looking for VidCast? It moved to https://vidcast.dabble.me/.".html_safe
  end
end
