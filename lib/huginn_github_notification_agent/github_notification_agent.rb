module Agents
  class GithubNotificationAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule '1h'

    description do
      <<-MD
      The Github notification agent fetches notifications and creates an event by notification.

      `mark_as_read` is used to post request for mark as read notification.

      `regex_filter_tag` is used to filter notification with tagname ( for example no beta/alpha).

      `add_release_details` is used when it's a notification release, it fetches tag_name/tarball_url/html_url.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:
        {
          "id": "xxxxx",
          "unread": true,
          "reason": "subscribed",
          "updated_at": "2020-06-27T14:44:56Z",
          "last_read_at": "2020-06-28T00:32:34Z",
          "subject": {
            "title": "xxxxxx",
            ...
            },
          "url": "https://api.github.com/notifications/threads/xxxxxx",
          "subscription_url": "https://api.github.com/notifications/threads/xxxxxx/subscription"
        }
    MD

    def default_options
      {
        'username' => '',
        'expected_receive_period_in_days' => '2',
        'token' => '',
        'regex_filter_tag' => '',
        'mark_as_read' => 'true',
        'add_release_details' => 'true'
      }
    end

    form_configurable :username, type: :string
    form_configurable :token, type: :string
    form_configurable :regex_filter_tag, type: :string
    form_configurable :mark_as_read, type: :boolean
    form_configurable :add_release_details, type: :boolean
    form_configurable :expected_receive_period_in_days, type: :string

    def validate_options
      unless options['username'].present?
        errors.add(:base, "username is a required field")
      end

      unless options['token'].present?
        errors.add(:base, "token is a required field")
      end

      if options.has_key?('add_release_details') && boolify(options['add_release_details']).nil?
        errors.add(:base, "if provided, add_release_details must be true or false")
      end

      if options.has_key?('mark_as_read') && boolify(options['mark_as_read']).nil?
        errors.add(:base, "if provided, mark_as_read must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      memory['last_status'].to_i > 0

      return false if recent_error_logs?
      
      if interpolated['expected_receive_period_in_days'].present?
        return false unless last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago
      end

      true
    end

    def check
      fetch
    end

    private

    def mark_read(repo_path)
      uri = URI.parse("https://api.github.com/repos/#{repo_path}/notifications")
      request = Net::HTTP::Put.new(uri)
      request.basic_auth("#{interpolated[:username]}", "#{interpolated[:token]}")
    
      req_options = {
        use_ssl: uri.scheme == "https",
      }
    
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
    
      log "mark as read request status for #{repo_path} : #{response.code}"
    end    
    
    def fetch
      uri = URI.parse("https://api.github.com/notifications")
      request = Net::HTTP::Get.new(uri)
      request.basic_auth("#{interpolated[:username]}", "#{interpolated[:token]}")
    
      req_options = {
        use_ssl: uri.scheme == "https",
      }
    
      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end
    
      log "fetch notification request status : #{response.code}"
    
      notification_json = JSON.parse(response.body)
    
      notification_json.each do |notif|
        if interpolated[:mark_as_read] == "true"
            mark_read(notif['repository']['full_name'])
        end
        if interpolated[:add_release_details] == "true" && notif['subject']['type'] == "Release"
            uri_bis = URI.parse(notif['subject']['url'])
            request_bis = Net::HTTP::Get.new(uri_bis)
            request_bis.basic_auth("#{interpolated[:username]}", "#{interpolated[:token]}")
          
            req_options_bis = {
              use_ssl: uri.scheme == "https",
            }
          
            response_bis = Net::HTTP.start(uri_bis.hostname, uri_bis.port, req_options_bis) do |http|
              http.request(request_bis)
            end
          
            log "fetch details request status for #{notif['repository']['full_name']} : #{response_bis.code}"
          
            details_json = JSON.parse(response_bis.body)
            notif.merge!({ :tagname => details_json['tag_name']})
            notif.merge!({ :tarball_url => details_json['tarball_url']})
            notif.merge!({ :changelog => details_json['html_url']})
        end
        if defined?(interpolated[:regex_filter_tag]) && (interpolated[:regex_filter_tag] != '')
            result = /#{interpolated[:regex_filter_tag]}/.match(details_json['tag_name'])
            log "regex filter enabled"
            if (result)
              then
                    create_event payload: notif
              else
                    log "matched by regex filter"
            end
        else
            create_event payload: notif
        end
      end
    end    
  end
end
