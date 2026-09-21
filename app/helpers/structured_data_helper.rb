module StructuredDataHelper
  SCHEMA_CONTEXT = "https://schema.org".freeze
  BRAND_NAME = "Dabble Me".freeze
  LEGAL_NAME = "Dabble Dev LLC".freeze
  SAME_AS = [
    "https://github.com/parterburn/dabble.me",
    "https://x.com/parterburn"
  ].freeze
  # Mirrors the pricing shown on the homepage and /subscribe (Stripe monthly/yearly).
  PRO_PRICES = { monthly: "4.00", yearly: "40.00" }.freeze

  # Renders a single JSON-LD <script>. One node gets its own @context; several nodes share an @graph.
  def json_ld_script_tag(*nodes)
    nodes = nodes.flatten
    payload = if nodes.one?
      { "@context": SCHEMA_CONTEXT }.merge(nodes.first)
    else
      { "@context": SCHEMA_CONTEXT, "@graph": nodes }
    end

    content_tag(:script, raw(json_escape(payload.to_json)), type: "application/ld+json")
  end

  def structured_data_base_url
    ApplicationHelper.site_public_base_url
  end

  def organization_json_ld
    base_url = structured_data_base_url
    {
      "@type": "Organization",
      "@id": "#{base_url}/#organization",
      name: BRAND_NAME,
      legalName: LEGAL_NAME,
      alternateName: "Dabble me.",
      url: "#{base_url}/",
      logo: {
        "@type": "ImageObject",
        url: "#{base_url}/android-chrome-512x512.png",
        width: 512,
        height: 512
      },
      sameAs: SAME_AS
    }
  end

  def website_json_ld
    base_url = structured_data_base_url
    {
      "@type": "WebSite",
      "@id": "#{base_url}/#website",
      url: "#{base_url}/",
      name: BRAND_NAME,
      alternateName: "Dabble me.",
      inLanguage: "en",
      publisher: { "@id": "#{base_url}/#organization" }
    }
  end

  # Free tier plus the two PRO plans. Deliberately has no aggregateRating: there is no review data to back one.
  def web_application_json_ld
    base_url = structured_data_base_url
    {
      "@type": "WebApplication",
      "@id": "#{base_url}/#webapplication",
      name: BRAND_NAME,
      url: "#{base_url}/",
      description: "A private journal that lives in your email inbox. Reply to a daily prompt to write an entry, and rediscover past entries automatically.",
      applicationCategory: "LifestyleApplication",
      operatingSystem: "Web",
      publisher: { "@id": "#{base_url}/#organization" },
      offers: [
        offer_json_ld("Dabble Me Free", "0.00"),
        offer_json_ld("Dabble Me PRO (monthly)", PRO_PRICES[:monthly]),
        offer_json_ld("Dabble Me PRO (yearly)", PRO_PRICES[:yearly])
      ]
    }
  end

  # Article/TechArticle node for a marketing page. Reads the page description from content_for(:description).
  def article_json_ld(headline:, path:, published:, modified:, type: "Article", about: nil)
    base_url = structured_data_base_url
    url = "#{base_url}#{path}"
    node = {
      "@type": type,
      headline: headline,
      description: content_for(:description),
      url: url,
      mainEntityOfPage: { "@type": "WebPage", "@id": url },
      image: "#{base_url}/dabble_logo_ogimage.jpg",
      datePublished: published,
      dateModified: modified,
      inLanguage: "en",
      author: { "@type": "Organization", name: BRAND_NAME, url: "#{base_url}/" },
      publisher: organization_json_ld
    }
    node[:about] = about if about.present?
    node
  end

  private

  def offer_json_ld(name, price)
    {
      "@type": "Offer",
      name: name,
      price: price,
      priceCurrency: "USD",
      availability: "https://schema.org/InStock",
      url: "#{structured_data_base_url}/subscribe"
    }
  end
end
