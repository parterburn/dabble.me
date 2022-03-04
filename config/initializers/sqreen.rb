sqreen = "Sqreen".constantize rescue nil
unless sqreen
  module Sqreen
    def self.method_missing(method, *args)
      # Silence is golden.
    end
  end
end
