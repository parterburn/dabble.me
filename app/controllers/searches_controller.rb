class SearchesController < ApplicationController
  before_action :authenticate_user!

  def show
    @search = Search.new(search_params)
    @entries = @search.entries unless current_user.is_free?

    if search_params[:term].blank?
      user_tags = current_user.used_hashtags(current_user.entries, false)
      @hashtags = []
      if user_tags.present?
        @hashtags = Hash[*user_tags.inject(Hash.new(0)) { |h,v| h[v] += 1; h }.sort_by{|k,v| v}.reverse.flatten]
      end
    end
  end

  private

  def search_params
    {term: permitted_term}.merge(user: current_user)
  end

  def permitted_term
    params.permit(search: :term).try(:[], 'search').try(:[], 'term')
  end
end
