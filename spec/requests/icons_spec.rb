# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Slab icons", type: :request do
  let(:source) { "https://dabble-me.s3.amazonaws.com/uploads/icons/slab/edit.svg" }
  let(:svg) { %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 576 576"><path d="M0 0"/></svg>) }

  it "serves the icon from our origin with public cache headers and no cookie" do
    stub_request(:get, source).to_return(status: 200, body: svg, headers: { "Content-Type" => "image/svg+xml" })

    get "/icons/slab/edit.svg"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/svg+xml")
    expect(response.body).to eq(svg)
    expect(response.headers["Cache-Control"]).to include("public")
    expect(response.headers["Content-Security-Policy"]).to include("default-src 'none'")
    expect(response.headers["Set-Cookie"]).to be_blank
  end

  it "is a 404 when S3 doesn't have the icon" do
    stub_request(:get, source).to_return(status: 403, body: "<Error/>")

    get "/icons/slab/edit.svg"

    expect(response).to have_http_status(:not_found)
  end

  it "won't pass along something that isn't an SVG" do
    stub_request(:get, source).to_return(status: 200, body: "<html><script>alert(1)</script></html>")

    get "/icons/slab/edit.svg"

    expect(response).to have_http_status(:not_found)
  end

  it "only fetches plain icon names" do
    expect { get "/icons/slab/..%2F..%2Fsecret.svg" }.to raise_error(ActionController::RoutingError)
    expect(WebMock).not_to have_requested(:get, /amazonaws/)
  end
end
