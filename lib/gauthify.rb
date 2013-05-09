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
    @headers = {:authorization => api_key, :user_agent => 'GAuthify-Ruby/v1.27'}

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


  def create_user(unique_id, display_name, email=nil, phone_number=nil)
    <<-DOC
        Creates new user (replaces with new if already exists)
    DOC

    params = {'display_name' => display_name}
    if email
      params['email'] = email
    end
    if phone_number
      params['phone_number'] = phone_number
    end
    url_addon = "users/#{unique_id}/"
    return requests_handler('post', url_addon, params=params)
  end

  def update_user(unique_id, email=nil, phone_number=nil, meta=nil, reset_key = false)
    <<-DOC
        Creates new user with a new secret key or resets if already exists
    DOC

    params = Hash.new
    if email
      params['email'] = email
    end
    if phone_number
      params['phone_number'] = phone_number
    end
    if meta
      params['meta'] = meta.to_json
    end
    if reset_key
      params['reset_key'] = 'true'
    end
    puts params
    url_addon = "users/#{unique_id}/"
    return requests_handler('put', url_addon, params=params)
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

  def get_user_by_token(unique_id)
    <<-DOC
        Returns a single user by ezGAuth token
    DOC
    url_addon = "token/#{unique_id}/"
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


  def send_sms(unique_id, phone_number = nil)
    <<-DOC
        Sends text message to phone number with the one time auth_code
    DOC
    url_addon = "users/#{unique_id}/sms/"
    if phone_number
      url_addon << "#{phone_number}/"
    end
    return requests_handler('get', url_addon)
  end

  def send_email(unique_id, email=nil)
    <<-DOC
        Sends email message to phone number with the one time auth_code
    DOC
    url_addon = "users/#{unique_id}/email/"
    if email
      url_addon << "#{email}/"
    end
    return requests_handler('get', url_addon)
  end

  def api_errors()
    <<-DOC
        Returns hash containing api errors.
    DOC
    url_addon = "errors/"
    return requests_handler('get', url_addon)
  end


  def quick_test(test_email = nil, test_number = nil)
    <<-DOC
        Runs initial tests to make sure everything is working fine
    DOC
    account_name = 'testuser@gauthify.com'

    def success()
      print("Success \n")
    end

    puts("1) Testing Creating a User...")
    result = create_user(account_name,
                         account_name, email='firsttest@gauthify.com',
                         phone_number='0123456789')
    if not result['unique_id'] == account_name
      raise Exception
    end
    if not result['display_name'] == account_name
      raise Exception
    end
    if not result['email'] == 'firsttest@gauthify.com'
      raise Exception
    end
    if not result['phone_number'] == '0123456789'
      raise Exception
    end
    puts(result)
    success()

    puts("2) Retrieving Created User...")
    user = get_user(account_name)
    if not user.class == Hash
      raise Exception
    end
    puts(user)
    success()

    puts("3) Retrieving All Users...")
    result = get_all_users()
    if not result.class == Array
      raise Exception
    end
    puts(result)
    success()

    puts("4) Bad Auth Code...")
    result = check_auth(account_name, '112345')
    if result
      raise Exception
    end
    puts(result)
    success()

    puts("5) Testing one time pass (OTP)....")
    result = check_auth(account_name, user['otp'])
    puts(result)
    if not result
      raise ParameterError('Server error. OTP not working. Contact ', 'support@gauthify.com for help.', 500, '500', '')
    end
    success()
    if test_email
      puts("5A) Testing email to #{test_email}")
      result = send_email(account_name, test_email)
      puts(result)
      success()
    end
    if test_number
      puts("5B) Testing SMS to #{test_number}")
      send_sms(account_name, test_number)
      success()
    end
    puts("6) Detection of provided auth...")
    result = get_user(account_name, 'test12')
    if not result['provided_auth']
      raise Exception
    end
    puts(result)
    success()

    puts("7) Testing updating email, phone, and meta")
    result = update_user(account_name, email='test@gauthify.com',
                         phone_number='1234567890', meta={'a' => 'b'})
    if not result['email'] == 'test@gauthify.com'
      raise Exception
    end
    if not result['phone_number'] == '1234567890'
      raise Exception
    end
    if not result['meta']['a'] == 'b'
      raise Exception
    end
    current_key = result['key']
    success()

    puts("8) Testing key/secret")
    result = update_user(account_name, nil, nil, nil, true)
    puts(current_key, result['key'])
    if not result['key'] != current_key
      raise Exception
    end
    success()

    puts("9) Deleting Created User...")
    result = delete_user(account_name)
    success()

    puts("10) Testing backup server...")
    current = @access_points[0]
    @access_points[0] = 'https://blah.gauthify.com/v1/'
    result = get_all_users()
    @access_points[0] = current
    puts(result)
    success()

  end
end
