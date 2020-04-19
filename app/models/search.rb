class Search
  include ActiveModel::Model

  attr_accessor :user, :term

  def entries
    if term.blank?
      []
    else
      user.entries.where("LOWER(body) LIKE ?", "%#{term.downcase}%")
    end
  end
end
