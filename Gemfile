# Gemfile
source 'https://rubygems.org'

# Core dependencies
gem 'pg', '~> 1.4'
gem 'mail', '~> 2.8'
gem 'prometheus-client', '~> 4.0'
gem 'rack', '~> 2.2'
gem 'puma', '~> 6.0'
gem 'oauth', '~> 1.1'

# Development and test dependencies
group :development, :test do
  gem 'rspec', '~> 3.12'
  gem 'rspec-mocks', '~> 3.12'
  gem 'rubocop', '~> 1.50'
  gem 'rubocop-rspec', '~> 2.20'
  gem 'simplecov', '~> 0.22'
  gem 'factory_bot', '~> 6.2'
  gem 'timecop', '~> 0.9'
end

group :development do
  gem 'pry', '~> 0.14'
  gem 'pry-byebug', '~> 3.10'
end

ruby '>= 2.7.0'