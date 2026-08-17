Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
     origins do |source, _env|
      [
        ENV.fetch(
          "FRONTEND_URL",
          "http://localhost:5173",
        ),
        "http://localhost:5173",
        "http://localhost",
        "capacitor://localhost",
      ].include?(source)
    end

    resource "*",
      headers: :any,
      expose: ["Authorization"],
      methods: %i[get post put patch delete options head]
  end
end
