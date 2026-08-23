require "googleauth"
require "json"
require "net/http"
require "stringio"
require "uri"

class FirebasePushService
  FIREBASE_SCOPE =
    "https://www.googleapis.com/auth/firebase.messaging"

  PROJECT_ID =
    ENV.fetch(
      "FIREBASE_PROJECT_ID",
      "matchmuster"
    )

  class << self
    def to_user(
      user:,
      title:,
      body:,
      data: {}
    )
      successful_deliveries = 0

      user.push_devices.find_each do |push_device|
        delivered =
          to_device(
            push_device: push_device,
            title: title,
            body: body,
            data: data
          )

        successful_deliveries += 1 if delivered
      end

      successful_deliveries
    end

    def to_device(
      push_device:,
      title:,
      body:,
      data: {}
    )
      response =
        send_request(
          token: push_device.token,
          title: title,
          body: body,
          data: data
        )

      if response.is_a?(Net::HTTPSuccess)
        Rails.logger.info(
          "Firebase push delivered to PushDevice #{push_device.id}"
        )

        true
      else
        Rails.logger.error(
          "Firebase push failed for PushDevice #{push_device.id}: " \
          "#{response.code} #{response.body}"
        )

        false
      end
    rescue StandardError => error
      Rails.logger.error(
        "Firebase push error for PushDevice #{push_device.id}: " \
        "#{error.class}: #{error.message}"
      )

      false
    end

    private

    def send_request(
      token:,
      title:,
      body:,
      data:
    )
      uri =
        URI(
          "https://fcm.googleapis.com/v1/projects/" \
          "#{PROJECT_ID}/messages:send"
        )

      request =
        Net::HTTP::Post.new(uri)

      request["Authorization"] =
        "Bearer #{access_token}"

      request["Content-Type"] =
        "application/json"

      request.body =
        {
          message: {
            token: token,
            notification: {
              title: title,
              body: body
            },
            data: normalize_data(data),
            android: {
              priority: "high",
              notification: {
                channel_id: "matchmuster_alerts"
              }
            }
          }
        }.to_json

      Net::HTTP.start(
        uri.hostname,
        uri.port,
        use_ssl: true
      ) do |http|
        http.request(request)
      end
    end

    def access_token
      credentials =
        Google::Auth::ServiceAccountCredentials.make_creds(
          json_key_io: credential_io,
          scope: FIREBASE_SCOPE
        )

      credentials
        .fetch_access_token!
        .fetch("access_token")
    end

    def credential_io
      service_account_json =
        ENV["FIREBASE_SERVICE_ACCOUNT_JSON"]

      if service_account_json.present?
        return StringIO.new(
          service_account_json
        )
      end

      File.open(
        ENV.fetch(
          "GOOGLE_APPLICATION_CREDENTIALS"
        )
      )
    end

    def normalize_data(data)
      data
        .compact
        .transform_keys(&:to_s)
        .transform_values(&:to_s)
    end
  end
end
