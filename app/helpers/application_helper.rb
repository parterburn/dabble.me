module ApplicationHelper
  def title(page_title)
    content_for(:title) { page_title.to_s }
  end

  def yield_or_default(section, default = '')
    content_for?(section) ? content_for(section) : default
  end

  def random_inspiration
    if (count = Inspiration.without_ohlife.count) > 0
      offset = rand(count)
      @inspiration = Inspiration.without_ohlife.offset(offset).first
      tag("p", :class=>"center s-inspiration") + @inspiration.body
    else
      ""
    end
  end  
end
