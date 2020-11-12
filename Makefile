# https://makefile.site - read about the approach

# run `make init` to get everything set up
init: sqreen dotenv
	rails db:create && rails db:environment:set RAILS_ENV=development && rails db:schema:load && rails db:migrate && rails db:seed

# it doesn't play any role, we just need it for the app to run
sqreen:
	echo "app_name: 'Dabble'\n\
	token: env_org_bbf331c7446f7935a9f82399ba9f20b276aa85ed1c3baaf5532cc32b" > config/sqreen.yml

# don't upload pictures and you'll be fine
dotenv:
	echo "ADMIN_EMAILS=your@email.com\n\
	AWS_ACCESS_KEY_ID=a\n\
	AWS_SECRET_ACCESS_KEY=b\n\
	AWS_BUCKET=c" > .env
