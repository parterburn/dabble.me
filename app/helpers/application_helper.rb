module ApplicationHelper
  def title(page_title)
    content_for(:title) { page_title.to_s }
  end

  def yield_or_default(section, default = '')
    content_for?(section) ? content_for(section) : default
  end

  def random_inspiration
    if (count = Inspiration.without_ohlife_or_email.count) > 0
      offset = rand(count)
      @inspiration = Inspiration.without_ohlife_or_email.offset(offset).first
      tag("div", :class=>"center s-inspiration") + @inspiration.body + "</div>".html_safe + hidden_field_tag("entry[inspiration_id]",@inspiration.id)
    else
      ""
    end
  end  
end
