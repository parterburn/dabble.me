# Dabble Me

I recommend forking and setting up a free server at [Ninefold](https://ninefold.com/).

It also uses [SendGrid](http://sendgrid.com) for processing emails. You can sign up for a free account that will allow 200 emails per day.

Your environment variables at ```config/local_env.yml``` will need to be:

```
SECRET_KEY_BASE=1234..1234
SENDGRID_USERNAME=your_sendgrid_username
SENDGRID_PASSWORD=your_sendgrid_password
DEVISE_SECRETE_KEY=1234..1234
```

If you want random bits of inspiration, you can load up different quotes in the Inspiration table to be shown above the New Posts page:

```Inspiration.create(:category => "question", :body => "Are you holding onto something you need to let go of?")

=====

Note: their is a directory at ```/public/cast``` that is not necessary for the Dabble Me site, but rather part of an existing Chromecast site (https://dabble.me/cast) that is running on Dabble.me and needs to be there for the site to still function. Feel free to remove if you setup Dabble Me on your own servers.