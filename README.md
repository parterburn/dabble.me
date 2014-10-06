# Dabble Me
### The open source replacement for OhLife

Dabble Me helps people remember what's happened in their life. Use it as a light-weight journal on a daily, weekly, or even monthly basis...it's up to you! Dabble Me will email you on a time & days you choose - you simply reply to the email to post entries. The app is live at (https://dabble.me)[https://dabble.me].

This app utilizes the following 3rd party services:

* [SendGrid](http://sendgrid.com) for Sending & Receiving Email (free for 200 emails per day)
* [Filepicker](http://filepicker.io) for Photo Uploads & Storage (free for 500 uploads per month)
* [MailChimp](http://mailchimp.com) for sending updates to all users (free for 2000 subscribers)
* [Google Analytics](http://google.com/analytis) for traffic stats (free for standard analytics)
* [New Relic](http://newrelic.com) for server monitoring (free for basic monitoring)

I recommend forking and setting up a free server at [Ninefold](https://ninefold.com/).

Your local environment variables at ```config/local_env.yml``` will need to be something like this:

```
SECRET_KEY_BASE: 1234..1234
DEVISE_SECRET_KEY: 1234..1234
SENDGRID_USERNAME: your_sendgrid_username
SENDGRID_PASSWORD: your_sendgrid_password
MAILCHIMP_API_KEY: f....3333-ek3
MAILCHIMP_LIST_ID: 9982...112
FILEPICKER_API_KEY: A....z
FILEPICKER_CDN_HOST: https://123abc.cloudfront.net
ADMIN_EMAILS: user1@domain.com,user2@domain.com
```

Your environment variables on Ninefold will need to be something like this:

```
SECRET_KEY_BASE=1234..1234
DEVISE_SECRETE_KEY=1234..1234
SENDGRID_USERNAME=your_sendgrid_username
SENDGRID_PASSWORD=your_sendgrid_password
NEW_RELIC_LICENSE_KEY=k3333..2222
NEW_RELIC_APP_NAME=DABBLE.ME
PROD_HOST=dabble.me
GOOGLE_ANALYTICS_ID=UA-12345-67
MAILCHIMP_API_KEY: f....3333-ek3
MAILCHIMP_LIST_ID: 9982...112
FILEPICKER_API_KEY: A....z
FILEPICKER_CDN_HOST: https://123abc.cloudfront.net
ADMIN_EMAILS: user1@domain.com,user2@domain.com
```

The Admin emails are accounts that have access to the Admin Dashboard at ```/admin``` that give you details into the number of entries and users in the system. It will estimate the usage of the 3rd party services so you can understand what price points running the app will fall in.

If you want random bits of inspiration, you can load up different quotes in the Inspiration table to be shown above the New Posts page and at the bottom of emails. If you plan on using OhLife, the sysytem will tag imported posts with ```inspiration_id``` of 1 - so create the first Inspiration with a category name of "OhLife".

```
Inspiration.create(:category => "OhLife", :body => "Imported from OhLife")
```

=====

**Current features:**

* Read past entries by month/year
* Create new entries with simple formatting
* OhLife Importer
* Email: Reply-to-post new entries on days of the week you choose (with random past entries embedded)
* Associate 1 image to a specific entry, additional images emailed in will add to the bottom of posts

**Features coming later:**

* Analytics around posting: when do you post, what do you post about mostly (tag cloud-esque)?

=====

Note: there is a directory at ```/public/cast``` that is not necessary for the journaling site, but rather part of an existing Chromecast site (https://dabble.me/cast) that is running on Dabble.me and needs to be there for the site to still function. Feel free to remove if you setup Dabble Me on your own servers.