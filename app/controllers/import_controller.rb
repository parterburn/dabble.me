require 'fileutils'

class ImportController < ApplicationController
  before_action :authenticate_user!
  SPLIT_AT_DATE_REGEX = /[12]{1}[90]{1}[0-9]{2}\-[0-1]{1}[0-9]{1}\-[0-3]{1}[0-9]{1}/

  def import_ohlife
  end

  def process_ohlife
    flash = import_ohlife_entries(params[:entry][:text])
    redirect_to entries_path
  end

  def process_ohlife_images
    tmp = params[:zip_file]
    if tmp && tmp.content_type == "application/zip"

      #mv uploaded ZIP file to /tmp/ohlife_zips
      dir = FileUtils.mkdir_p("public/ohlife_zips/#{current_user.user_key}")
      file = File.join(dir, tmp.original_filename)
      FileUtils.mv tmp.tempfile.path, file
      count = 0
      error_count = 0
      errors = []
      Zip::File.open(file) { |zip_file|
        zip_file.each { |f|
          f_path=File.join(dir, "unzipped", f.name)
          FileUtils.mkdir_p(File.dirname(f_path))
          zip_file.extract(f, f_path) unless File.exist?(f_path)
          if f.name =~ /^img_[12]{1}[90]{1}[0-9]{2}-[0-9]{2}-[0-9]{2}-0\.(jpe?g|gif|png)$/i
            date = f.name.scan(SPLIT_AT_DATE_REGEX)[0]
            existing_entry = current_user.existing_entry(date.to_s)
            if existing_entry.present?
              #existing entry exists, process through filepicker and save
              img_url = CGI.escape "https://dabble.me/#{f_path.gsub("public/","")}"
              begin
                response = MultiJson.load RestClient.post("https://www.filepicker.io/api/store/S3?key=#{ENV['FILEPICKER_API_KEY']}&url=#{img_url}", nil), :symbolize_keys => true
                if response[:url].present?
                  if existing_entry.image_url.present?
                    img_url_cdn = response[:url].gsub("https://www.filepicker.io", ENV['FILEPICKER_CDN_HOST'])
                    existing_entry.body += "<hr><div class='pictureFrame'><a href='#{img_url_cdn}' target='_blank'><img src='#{img_url_cdn}/convert?fit=max&w=300&h=300&cache=true&rotate=:exif' alt='#{existing_entry.date.strftime("%b %-d")}'></a></div>"
                  else
                    existing_entry.image_url = response[:url]
                  end
                  existing_entry.save
                  count+=1
                else
                  error_count+=1
                  errors << date
                end
              rescue
                error_count+=1
                errors << date
              end
            end
          end
        }
      }

      #delete folder:
      FileUtils.rm_r dir, :force => true
      
      flash[:notice] = "Finished importing #{ActionController::Base.helpers.pluralize(count,'photo')}" if count > 0
      flash[:alert] = "Error importing #{ActionController::Base.helpers.pluralize(error_count,'photo')}" if error_count > 0
      errors.each do |error|
        flash[:alert] << "<br>"+error
      end
      redirect_to entries_path
    else
      FileUtils.rm tmp.tempfile.path if tmp
      flash[:alert] = "Only ZIP files are allowed here."
      redirect_to import_ohlife_path
    end

  end

  private

    def import_ohlife_entries(data)
      errors = []
      user = current_user #protect users from importing into someone else's entries

      dates = data.scan(SPLIT_AT_DATE_REGEX)
      bodies  = data.split(SPLIT_AT_DATE_REGEX)
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