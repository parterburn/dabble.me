# Dabble Me

I recommend forking and setting up a free server at [Ninefold](https://ninefold.com/).

It also uses [SendGrid](http://sendgrid.com) for processing emails. You can sign up for a free account that will allow 200 emails per day.

Your local environment variables at ```config/local_env.yml``` will need to be something like this:

```
SENDGRID_USERNAME: your_sendgrid_username
SENDGRID_PASSWORD: your_sendgrid_password
SECRET_KEY_BASE: 1234..1234
DEVISE_SECRET_KEY: 1234..1234
```

Your environment variables on Ninefold will need to be something like this:

```
SENDGRID_USERNAME=your_sendgrid_username
SENDGRID_PASSWORD=your_sendgrid_password
SECRET_KEY_BASE=1234..1234
DEVISE_SECRETE_KEY=1234..1234
NEW_RELIC_LICENSE_KEY=k3333..2222
NEW_RELIC_APP_NAME=DABBLE.ME
PROD_HOST=dabble.me
GOOGLE_ANALYTICS_ID=UA-12345-67
```

If you want random bits of inspiration, you can load up different quotes in the Inspiration table to be shown above the New Posts page:

```Inspiration.create(:category => "question", :body => "Are you holding onto something you need to let go of?")

=====

Note: their is a directory at ```/public/cast``` that is not necessary for the Dabble Me site, but rather part of an existing Chromecast site (https://dabble.me/cast) that is running on Dabble.me and needs to be there for the site to still function. Feel free to remove if you setup Dabble Me on your own servers.