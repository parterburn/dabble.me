class ValidDateValidator < ActiveModel::EachValidator

  def validate_each(record,attribute,value)
    begin
       DateTime.parse(value.to_s)
    rescue ArgumentError
      record.errors[attribute] << "does not seem to be valid"
    end
  end  

end