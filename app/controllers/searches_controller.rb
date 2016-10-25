class SearchesController < ApplicationController
  before_filter :authenticate_user!

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

    hashtagged_entries = current_user.entries.where("entries.body ~ '(#[a-zA-Z0-9_]+)'")
    @hashtags = []
    hashtagged_entries.each do |entry|
      entry.body.scan(/(<a[^>]*>.*?< ?\/a ?>)|(#[0-9]+\W)|(#[a-zA-Z0-9_]+)/) { |m| @hashtags << m[2] }
    end
    @hashtags.compact!
    @hashtags = @hashtags.map{|i| i.downcase}.uniq.sort_by!{ |m| m.downcase }.inject({}) {|accu, uni| accu.merge({ uni => @hashtags.select{|i| i.downcase == uni.downcase } })}
  end

  private

  def search_params
    permitted_params.fetch(:search, {}).merge(user: current_user)
  end

  def permitted_params
    params.permit(:commit, :utf8, search: :term)
  end
end