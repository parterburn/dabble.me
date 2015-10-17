# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :entry, class: 'Entries' do
    user nil
  end
end
