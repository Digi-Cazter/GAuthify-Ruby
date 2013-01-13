require 'net/http'
require 'uri'
require 'rest-client'
require 'json'

class GAuthifyError < Exception
    <<-DOC
    All Errors
    DOC

    attr_reader :msg, :http_status, :error_code, :response_body

    def initialize(msg, http_status = '', error_code = '', response_body='')
        @msg = msg
        @http_status = http_status
        @error_code = error_code
        @response_body = response_body
    end
end

class ApiKeyError < GAuthifyError
    <<-DOC
    Raised when API Key is incorrect
    DOC
end

class ParameterError < GAuthifyError
    <<-DOC
    Raised when submitting bad parameters or missing parameters
    DOC
end


class NotFoundError < GAuthifyError
    <<-DOC
    Raised when a result isn't found for the parameters provided.
    DOC
end


class ServerError < GAuthifyError
    <<-DOC
    Raised for any other error that the server can give, mainly a 500
    DOC
end

class RateLimitError < GAuthifyError
    <<-DOC
    Raised when API limit reached either by lack of payment or membership limit
    DOC
end


class GAuthify

    attr_accessor :headers, :access_points

    def initialize(api_key)
        @access_points = [
          'https://api.gauthify.com/v1/',
          'https://backup.gauthify.com/v1/'
        ]
        @headers = {:authorization => api_key, :user_agent => 'GAuthify/v1.00 Ruby/1.00'}

    end

    def requests_handler(type, url_addon='', params={})
        type = type.downcase
        for each in @access_points
            begin
                req_url = each + url_addon
                req = RestClient::Request.execute(:method => type, :url => req_url, :timeout => 1.5, :headers => @headers, :payload => params)
                status_code = req.code
                begin
                    json_resp = JSON.parse(req.to_str)
                rescue
                    json_resp = false
                end
                if not json_resp.is_a? Hash or (status_code > 400 and not [401, 402, 406, 404].include?(status_code))
                    raise RestClient::Exception
                end
                break
            rescue Exception => e
                if e.is_a? RestClient::Exception
                    case e.http_code
                        when 401
                            json_resp = JSON.parse(e.http_body)
                            raise ApiKeyError.new(json_resp['error_message'], status_code, json_resp['error_code'], e.http_body), json_resp['error_message']
                        when 402
                            json_resp = JSON.parse(e.http_body)
                            raise RateLimitError.new(json_resp['error_message'], status_code, json_resp['error_code'], e.http_body), json_resp['error_message']
                        when 406
                            json_resp = JSON.parse(e.http_body)
                            raise ParameterError.new(json_resp['error_message'], status_code, json_resp['error_code'], e.http_body), json_resp['error_message']
                        when 404
                            json_resp = JSON.parse(e.http_body)
                            raise NotFoundError.new(json_resp['error_message'], status_code, json_resp['error_code'], e.http_body), json_resp['error_message']
                    end
                end
                if each == @access_points[-1]
                    e_msg = "#{e.to_s}. Please contact support@gauthify.com for help"
                    raise ServerError.new(e_msg, 500, '500', ''), e_msg
                end
                next
            end
        end
        return json_resp['data']
    end


    def create_user(unique_id, display_name)
        <<-DOC
    Creates or upserts a new user with a new secret key
        DOC

        params = {'display_name' => display_name}
        url_addon = "users/#{unique_id}/"
        return requests_handler('post', url_addon, params=params)
    end

    def delete_user(unique_id)
        <<-DOC
      Deletes user given by unique_id
        DOC
        url_addon = "users/#{unique_id}/"
        return requests_handler('delete', url_addon)

    end

    def get_all_users()
        <<-DOC
        Retrieves a list of all users
        DOC
        return requests_handler('get', 'users/')
    end


    def get_user(unique_id, auth_code=nil)
        <<-DOC
        Returns a single user, checks the otp if provided
        DOC
        url_addon = "users/#{unique_id}/"
        url_addon << "check/#{auth_code}" if auth_code
        return requests_handler('get', url_addon)
    end

    def check_auth(unique_id, auth_code, safe_mode = false)
        <<-DOC
        Checks OTP returns True/False depending on OTP correctness.
        DOC
        begin
            response = get_user(unique_id, auth_code)
            if not response['provided_auth']
                raise ParameterError('auth_code not detected. Check if params sent via get request.')
            end
            return response['authenticated']
        rescue GAuthifyError => e
            if safe_mode
                return True
            else
                raise e
            end
        end

    end


    def send_sms(unique_id, phone_number)
        <<-DOC
        Sends text message to phone number with the one time auth_code
        DOC
        url_addon = "users/#{unique_id}/sms/#{phone_number}"
        return requests_handler('get', url_addon)
    end

    def send_email(unique_id, email)
        <<-DOC
        Sends email message to phone number with the one time auth_code
        DOC
        url_addon = "users/#{unique_id}/email/#{email}"
        return requests_handler('get', url_addon)
    end


    def quick_test(test_email = nil, test_number = nil)
        <<-DOC
        Runs initial tests to make sure everything is working fine
        DOC
        account_name = 'testuser@gauthify.com'
        puts("1) Testing Creating a User...")
        result = create_user(account_name,
                             account_name)
        puts result
        puts("Success ")
        puts("2) Retrieving Created User...")
        user = get_user(account_name)
        puts user
        puts("Success ")
        puts("3) Retrieving All Users...")
        result = get_all_users()
        puts result
        puts("Success ")
        puts("4) Bad Auth Code...")
        result = check_auth(account_name, '112345')
        puts(result)
        if result
            raise Exception
        end
        puts("Success ")
        puts("5) Testing one time pass (OTP)....")
        result = check_auth(account_name, user['otp'])
        puts(result)
        if not result
            raise Exception
        end
        if test_email
            puts("5A) Testing email to #{test_email}....")
            result = send_email(account_name, test_email)
            puts(result)
        end
        if test_number
            puts("5B) Testing SMS to #{test_number}....")
            result = send_sms(account_name, test_number)
            puts(result)
        end
        puts("Success ")
        puts("6) Detection of provided auth...")
        result = get_user(account_name, 'test12')['provided_auth']
        if not result
            raise Exception
        end
        puts("7) Deleting Created User...")
        result = delete_user(account_name)
        puts(result)
        puts("Success ")


        puts("8) Testing backup server...")
        @access_points[0] = 'https://blah.gauthify.com/v1/'
        results = get_all_users()
        @access_points[0] = 'https://api.gauthify.com/v1/'
        puts(result)
        puts("Tests Look Good.")
    end


end

