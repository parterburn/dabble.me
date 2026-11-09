require "rails_helper"

# public/app-tailwind.css loads on restyled pages next to the legacy styles, and
# its utilities are !important. If it defines a class the shared navbar or
# footer also uses (e.g. `flex`), the Tailwind rule silently wins there.
RSpec.describe "public/app-tailwind.css" do
  let(:css) { Rails.root.join("public/app-tailwind.css").read }

  let(:tailwind_classes) do
    css.scan(/\.((?:\\.|[\w-])+)/).flatten.map { |name| name.delete("\\") }.to_set
  end

  let(:layout_classes) do
    %w[layouts/application shared/_navbar shared/_footer].flat_map do |view|
      source = Rails.root.join("app/views/#{view}.html.erb").read
      source.scan(/class(?:=|:\s*)["']([^"'<]*)["']/).flatten.flat_map(&:split)
    end.to_set
  end

  it "defines no class that the shared layout also uses" do
    expect(layout_classes).not_to be_empty
    expect(tailwind_classes & layout_classes).to be_empty
  end
end
