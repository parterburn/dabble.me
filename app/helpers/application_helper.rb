module ApplicationHelper
  def title(page_title)
    content_for(:title) { page_title.to_s }
  end

  def yield_or_default(section, default = '')
    content_for?(section) ? content_for(section) : default
  end

  def random_inspiration
    offset = rand(Inspiration.count)
    @inspiration = Inspiration.offset(offset).first
    @inspiration.body
  end  
end
