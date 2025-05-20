release: bin/release
web: bundle exec puma -p $PORT -C config/puma.rb
worker: RUBY_YJIT_ENABLE=1 bundle exec sidekiq -c 6
