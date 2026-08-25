namespace :subscriptions do
  desc "Audit production subscription configuration without printing secrets"
  task audit: :environment do
    result = StoreSubscriptionProductionReadiness.call

    puts "Subscription production configuration: OK"
    puts "Apple environment: #{result.fetch(:apple_environment)}"
    puts "Google credentials: #{result.fetch(:google_credentials)}"
    puts "Store API open timeout: #{result.fetch(:open_timeout_seconds)} seconds"
    puts "Store API read timeout: #{result.fetch(:read_timeout_seconds)} seconds"
  rescue StoreSubscriptionProductionReadiness::ConfigurationError => error
    warn error.message
    abort "Subscription production configuration audit failed"
  end
end
