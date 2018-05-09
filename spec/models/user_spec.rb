require 'rails_helper'

describe User do
  let(:user) { User.create(email: Faker::Internet.email, password: Faker::Internet.password(8), first_name: Faker::Name.first_name, last_name: Faker::Name.last_name) }

  before :each do
    user.entries.create(body: "hi.", date: 2.days.ago)
    user.entries.create(body: "hi.", date: 3.days.ago)
    user.entries.create(body: "hi.", date: 4.days.ago)
    user.entries.create(body: "hi.", date: 5.days.ago)
  end

  describe "#random_entry" do
    it "returns leap year entry" do
      entry_date = Date.parse("2020-2-29")
      past_entry = user.entries.create(date: Date.parse("2016-2-29"), body: "Hi from past leap year.")
      user.way_back_past_entries = true
      expect(user.random_entry(entry_date)).to eq(past_entry)
    end

    it "returns same day, way back" do
      entry_date = Date.parse("2018-10-5")
      past_entry = user.entries.create(date: Date.parse("2002-10-5"), body: "Hi from way back.")
      user.way_back_past_entries = true
      expect(user.random_entry(entry_date)).to eq(past_entry)
    end

    it "returns 1 year ago" do
      entry_date = Date.parse("2018-10-5")
      past_entry = user.entries.create(date: Date.parse("2017-10-5"), body: "Hi from 1 year back.")
      user.way_back_past_entries = false
      expect(user.random_entry(entry_date)).to eq(past_entry)
    end

    it "returns 1 month ago" do
      user.emails_sent = 3
      entry_date = Date.parse("2018-10-5")
      past_entry = user.entries.create(date: Date.parse("2018-9-5"), body: "Hi from 1 month back.")
      expect(user.random_entry(entry_date)).to eq(past_entry)
    end

    it "returns 1 week ago" do
      user.way_back_past_entries = false
      user.emails_sent = 5
      entry_date = Date.parse("2018-10-5")
      past_entry = user.entries.create(date: Date.parse("2018-9-28"), body: "Hi from 1 week back.")
      expect(user.random_entry(entry_date)).to eq(past_entry)
    end    

    it "returns random from way back" do
      user.emails_sent = 2
      user.way_back_past_entries = true
      entry_date = Date.parse("2018-10-5")
      (1..30).each do |i|
        user.entries.create(date: Date.parse("2015-1-#{i}"), body: "Hi from way back.")
      end
      expect(user.random_entry(entry_date).date.year).to eq(2015)
    end   

    it "returns pure random, way back" do
      user.way_back_past_entries = true
      entry_date = Date.parse("2018-10-5")
      user.entries.create(date: Date.parse("2015-1-15"), body: "Hi from way back.")
      expect(user.random_entry(entry_date).date.year).to eq(2015)
    end       

    it "returns pure random, not way back" do
      user.way_back_past_entries = false
      entry_date = Date.parse("2018-10-5")
      user.entries.create(date: Date.parse("2015-1-15"), body: "Hi from way back.")
      user.entries.create(date: Date.parse("2018-10-3"), body: "Hi from a few days ago.")
      expect(user.random_entry(entry_date).date.year).to_not eq(2015)
    end           

  end
end