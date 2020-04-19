class SearchesController < ApplicationController
  before_action :authenticate_user!

  def show
    if current_user.is_free?
      @search = Search.new(search_params)
    elsif search_params[:term].present? && search_params[:term].include?(" OR ")
      @search = Search.new(search_params)
      filter_names = search_params[:term].split(' OR ')
      cond_text = filter_names.map{|w| "LOWER(entries.body) like ?"}.join(" OR ")
      cond_values = filter_names.map{|w| "%#{w}%"}
      @entries = current_user.entries.where(cond_text, *cond_values)
    else
      @search = Search.new(search_params)
      @entries = @search.entries
    end

    if search_params[:term].blank?
      hashtagged_entries = current_user.entries.where("entries.body ~ '(#[a-zA-Z0-9_]+)'")
      @hashtags = []
      hashtagged_entries.each do |entry|
        entry.body.scan(/#([0-9]+[a-zA-Z_]+\w*|[a-zA-Z_]+\w*)/) { |m| @hashtags << m[0] }
      end
      @hashtags.compact!
      @hashtags = @hashtags.map{|i| i.downcase}.uniq.sort_by!{ |m| m.downcase }.inject({}) {|accu, uni| accu.merge({ uni => @hashtags.select{|i| i.downcase == uni.downcase } })}
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
