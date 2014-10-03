class ImportController < ApplicationController
  before_action :authenticate_user!

  def import_ohlife
  end

  def process_ohlife
    flash = import_ohlife_entries(params[:entry][:text])
    redirect_to entries_path
  end

  private

    def import_ohlife_entries(data)
      errors = []
      user = current_user #protect users from importing into someone else's entries

      split_at_date_regex = /[1-2]{1}[0-9]{1}[0-9]{2}\-[0-1]{1}[0-9]{1}\-[0-3]{1}[0-9]{1}/
      dates = data.scan(split_at_date_regex)
      bodies  = data.split(split_at_date_regex)
      bodies.shift

      dates.each_with_index do |date,i|
        #remove line breaks at begininng and end          
        body = ActionController::Base.helpers.simple_format(bodies[i])
        body.gsub!(/\A(\<p\>\<\/p\>)/,"")
        body.gsub!(/(\<p\>\<\/p\>)\z/,"")
        entry = user.entries.create(:date => date, :body => body, :inspiration_id => 1)
        unless entry.save
          errors << date
        end
      end

      flash[:notice] = "Finished importing " + ActionController::Base.helpers.pluralize(dates.count,"entry")
      if errors.present?
        flash[:alert] = "<strong>"+ActionController::Base.helpers.pluralize(errors.count,"error") + " while importing:</strong>"
        errors.each do |error|
          flash[:alert] << "<br>"+error
        end
      end
    end   

    def import_ohlife_images(data)
      require 'zip'

      Zip::File.open("my.zip") do |zipfile|
        zipfile.each do |file|
          # do something with file
        end
      end      
    end    

end