class SearchesController < ApplicationController
  before_action :authenticate_user!

  def show
    if current_user.is_free?
      @search = Search.new(search_params)
    elsif search_params[:term].present? && search_params[:term].include?(" OR ")
      @search = Search.new(search_params)
      filter_names = search_params[:term].split(' OR ')
      cond_text = filter_names.map{|w| "LOWER(entries.body) like ?"}.join(" OR ")
      cond_values = filter_names.map{|w| "%#{w.downcase}%"}
      @entries = current_user.entries.where(cond_text, *cond_values)
    elsif search_params[:term].present? && search_params[:term].include?('"')
      @search = Search.new(search_params)
      exact_phrase = search_params[:term].delete('"')
      @entries = current_user.entries.where("entries.body ~* ?", "\\m#{exact_phrase}\\M")
    else
      @search = Search.new(search_params)
      @entries = @search.entries
    end

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
