class CreateFrequencyField < ActiveRecord::Migration[6.0]  
  def up
    add_column :users, :frequency_upd, :text, array: true, default: ["Sun"]

    User.find_each do |user|
      freqs = []
      f = user.read_attribute(:frequency).to_s

      freqs << "Sun" if "Sun".in?(f)
      freqs << "Mon" if "Mon".in?(f)
      freqs << "Tue" if "Tue".in?(f)
      freqs << "Wed" if "Wed".in?(f)
      freqs << "Thu" if "Thu".in?(f)
      freqs << "Fri" if "Fri".in?(f)
      freqs << "Sat" if "Sat".in?(f)

      user.frequency_upd = freqs
      user.save
    end

    remove_column :users, :frequency
    rename_column :users, :frequency_upd, :frequency
  end
end
