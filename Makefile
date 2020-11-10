# run `make init` to get everything set up
init: sqreen dotenv
	rails db:create && rails db:environment:set RAILS_ENV=development && rails db:schema:load && rails db:migrate && rails db:seed
	make sqreen

# it doesn't play any role, we just need it for the app to run
sqreen:
	cat > config/sqreen.yml <<EOF
	app_name: "Dabble"
	token: env_org_bbf331c7446f7935a9f82399ba9f20b276aa85ed1c3baaf5532cc32b
	EOF

# don't upload pictures and you'll be fine
dotenv:
	cat > .env <<EOF
	ADMIN_EMAILS=your@email.com
	AWS_ACCESS_KEY_ID=a
	AWS_SECRET_ACCESS_KEY=b
	AWS_BUCKET=c
	EOF
