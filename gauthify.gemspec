Gem::Specification.new do |s|
  s.name        = 'gauthify'
  s.version     = '1.2.71'
  s.date        = '2013-05-08'
  s.summary     = ""
  s.description = "API library for GAuthify.com (Google Authenticator, SMS, email multi factor authentication)."
  s.authors     = ["GAuthify"]
  s.email       = 'support@gauthify.com'
  s.files       = ["lib/gauthify.rb"]
  s.add_dependency('rest-client', '= 1.6.7')
  s.homepage    =
    'https://www.gauthify.com'
end
