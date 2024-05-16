# Dabble Me
### A private journal over email service.

Dabble Me helps people remember what's happened in their life. Use it as a light-weight journal on a daily, weekly, or even monthly basis...it's up to you! Dabble Me will email you on a time & days you choose - you simply reply to the email to post entries. The app is live at [https://dabble.me](https://dabble.me). This is a great replacement if you had ever used [OhLife](http://ohlife.com).

This app utilizes the following 3rd party services:

* [CloudFlare](http://cloudflare.com) managed DNS + free SSL support (free for basic service)
* [Mailgun](http://www.mailgun.com/rackspace) for Sending & Receiving Email (free for 50k emails per month)
* [Amazon S3](http://aws.amazon.com) for Photo Uploads & Storage (free for 1 year)
* [MailChimp](http://mailchimp.com) for sending updates to all users (free for 2,000 subscribers)
* [Google Analytics](http://google.com/analytics) for traffic stats (free for standard analytics)
* [Turnstile](https://www.cloudflare.com/products/turnstile/) to prevent bot signups (free).
* [Sentry](https://www.sentry.io/) to report errors (free)
* [Clarifai](https://www.clarifai.com/) to analyze images for legality (free up to 5,000/mo)

You will need to setup Mailgun to receive incoming emails and point them to your app to parse.

In order to turn on scheduled emails in Heroku, you'll need to add an hourly job using the Heroku Scheduler.
```
rake entry:send_hourly_entries
```

Your local environment variables at ```config/local_env.yml``` (and on Heroku) will need to be something like this (```rake db:seed``` will create the admin@dabble.ex account for you):

```yaml
MAIN_DOMAIN: yourdomain.com
SECRET_KEY_BASE: 1234..1234
DEVISE_SECRET_KEY: 1234..1234
SMTP_DOMAIN: post.yourdomain.com
MAILGUN_API_KEY=api-key
MAILCHIMP_API_KEY: f....3333-ek3
MAILCHIMP_LIST_ID: 9982...112
TURNSTILE_SITE_KEY: 6Lc6BAAAAAAAAChqRbQZcn_yyyyyyyyyyyyyyyyy
TURNSTILE_SECRET_KEY: 6Lc6BAAAAAAAAKN3DRm6VA_xxxxxxxxxxxxxxxxx
CLARIFAI_PERSONAL_ACCESS_TOKEN: asdl2k34jl2kn1l2hn234
CLARIFAI_THRESHOLD: 0.5
GOOGLE_ANALYTICS_ID=UA-12345-67 ## ONLY FOR PRODUCTION
SENTRY_DSN: https://dsn.sentry.io/1234
OPENAI_ACCESS_TOKEN: sk-1234
OPENAI_ORGANIZATION_ID: org-1234
HUGGING_FACE_API_KEY: 1234
STRIPE_API_KEY: sk_test_1234
STRIPE_SIGNING_SECRET: whsec_1234
```

### Things you may want to rip out

If you want to bypass using Mailchimp to collect email addresses, simply don't put a value in for `MAILCHIMP_API_KEY`. I use Mailchimp to email out new features to the users at Dabble.me, so if you're the only one using your app it doesn't make sense to have Mailchimp.

Same for Turnstile and Clarafai: simply don't add an environment variables for `TURNSTILE_SITE_KEY`, `CLARIFAI_V2_API_KEY`.


### Tests

There is healthy coverage of the app, which you can run with:

```
rake
```

### Administration Portal

The Admin emails are accounts that have access to the Admin Dropdown in the navbar (lock icon) that give you details into the number of entries and users in the system.

### Inspirations and OhLife Importer

If you want random bits of inspiration, you can load up different quotes in the Inspiration table to be shown above the New Posts page and at the bottom of emails. If you plan on using OhLife, the system will tag imported posts with ```inspiration_id``` of 1 - so create the first Inspiration with a category name of "OhLife".

```ruby
Inspiration.create(category: 'OhLife', body: 'Imported from OhLife')
```

=====

**Current features:**

* Read past entries by month/year
* Create new entries with simple formatting
* OhLife Importer
* Email: Reply-to-post new entries on days of the week you choose (with random past entries embedded)
* Associate 1 image to a specific entry
* Search with basic analytics around posting
* Hashtag support for tagging your entries
* Year in Review
