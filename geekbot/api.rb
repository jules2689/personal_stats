require 'json'
require 'net/http'

module Geekbot
  class API
    ROOT_URL = "https://api.geekbot.io/v1"
    private_constant :ROOT_URL

    FetchError = Class.new(RuntimeError)

    class << self
      def standups
        get("#{ROOT_URL}/standups")
      end

      def standup(id)
        get("#{ROOT_URL}/standup/#{id}")
      end

      def reports(standup_id, after = nil)
        params = {
          standup_id: standup_id,
          limit: 100,
        }
        params[:after] = after if after
        get("#{ROOT_URL}/reports", params)
      end

      private

      def get(url, params = {}, limit = 10)
        raise FetchError, 'HTTP redirect too deep' if limit == 0

        parsed_url = URI.parse(url)

        http = Net::HTTP.new(parsed_url.host, parsed_url.port)
        http.use_ssl = true

        request = Net::HTTP::Get.new(parsed_url.path + "?" + URI.encode_www_form(params))
        request['Authorization'] = ENV['GEEKBOT_TOKEN']
        request.set_form_data(params)

        response = http.request(request)

        case response
        when Net::HTTPSuccess     then JSON.parse(response.body)
        when Net::HTTPRedirection then get(response['location'], params, limit - 1)
        else
          response.error!
        end
      end
    end
  end
end
