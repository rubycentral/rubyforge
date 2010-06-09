# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_rubyforge_session',
  :secret      => 'cdc697fc9d9e71869d3c675c4e69cc6e70b0356bb060e3eff4270d6f6eaa812abad65cd57a2ae998a1f93ba42e4bda18d6a385526d48f8ad24831cbbd9e80ef4'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store
