#  == Used for interfacing the Yext API

require 'net/http'
require 'uri'
require 'xmlsimple'

class Yext

  # setup base credentials
  BASE_URL      = Rails.env == 'production' ? 'https://api.yext.com' : 'https://api-sandbox.yext.com'
  YEXT_OFFER_ID = Rails.env == 'production' ? 'PRODUCTION_ID' : 'DEV_ID'
  API_KEY       = Rails.env == 'production' ? 'PRODUCTION_KEY' : 'DEV_KEY'

  #
  #  Yext resources
  #

  def create_customer(profile)
    xml = assemble_xml(profile, 'new_customer') #(record, xml_template_to_use)
    respond_with_hash post("#{BASE_URL}/v1/customers?api_key=#{API_KEY}", :body => xml)
  end

  def recreate_customer(profile) # used in case Yext failed to accept changes upon initial creation
    xml = assemble_xml(profile, 'new_customer')
    respond_with_hash post("#{BASE_URL}/v1/customers?api_key=#{API_KEY}", :body => xml)
  end

  def update_customer(customer)
    xml = assemble_xml(customer, 'customer')
    respond_with_hash put("#{BASE_URL}/v1/customers/#{customer.yext_customer_id}?api_key=#{API_KEY}", :body => xml)
  end

  def create_location(location)
    xml = assemble_xml(location, 'location')
    respond_with_hash post("#{BASE_URL}/v1/customers/#{location.business_profile.yext_customer_id}/locations?api_key=#{API_KEY}", :body => xml)
  end

  def add_location_to_subscription(location)
    xml = "Request to add location to subscription."
    respond_with_hash put("#{BASE_URL}/v1/customers/#{location.business_profile.yext_customer_id}/subscriptions/#{location.business_profile.yext_subscription_id}/locationIds/#{location.yext_location_id}?api_key=#{API_KEY}", :body => xml)
  end

  def update_location(location)
    xml = assemble_xml(location, 'location')
    respond_with_hash put("#{BASE_URL}/v1/customers/#{location.business_profile.yext_customer_id}/locations/#{location.yext_location_id}?api_key=#{API_KEY}", :body => xml)
  end

  def remove_location(location)
    xml = "Request to remove location from subscription."
    respond_with_hash delete("#{BASE_URL}/v1/customers/#{location.business_profile.yext_customer_id}/subscriptions/#{location.business_profile.yext_subscription_id}/locationIds/#{location.yext_location_id}?api_key=#{API_KEY}", :body => xml)
  end

  def cancel_subscription(customer)
    xml = assemble_xml(customer, 'cancel_subscription')
    respond_with_hash put("#{BASE_URL}/v1/customers/#{customer.yext_customer_id}/subscriptions/#{customer.yext_subscription_id}?api_key=#{API_KEY}", :body => xml)
  end

  def listing_status(customer)
    respond_with_raw get("#{BASE_URL}/v1/powerlistings/status?api_key=#{API_KEY}&customerId=#{customer.yext_customer_id}", :content_type => 'application/x-www-form-urlencoded', :body => '')
  end

  def listing_performance(customer)
    respond_with_raw get("#{BASE_URL}/v1/powerlistings/reporting?api_key=#{API_KEY}&customerId=#{customer.yext_customer_id}&rowAxis=DAYS&columnAxis=VALUES&filterStart=2012-02-01&filterEnd=2012-03-30&filterValues=PROFILEVIEWS&filterValues=SEARCHES", :content_type => 'application/x-www-form-urlencoded', :body => '')
  end

  # currently using native Yext categories so this method is depricated.
  def fetch_categories
    xml = "Request categories."
    respond_with_raw get("#{BASE_URL}/v1/categories?api_key=#{API_KEY}&format=json", :body => xml)
  end

  #
  # REST handlers
  #

  def get(url, options = {})
    execute(url, options)
  end

  def put(url, options = {})
    options = {:method => :put}.merge(options)
    execute(url, options)
  end

  def post(url, options = {})
    options = {:method => :post}.merge(options)
    execute(url, options)
  end

  def delete(url, options = {})
    options = {:method => :delete}.merge(options)
    execute(url, options)
  end

  protected

  def respond_with_hash(response)
    XmlSimple.xml_in(response.body, { 'ForceArray' => false, 'SuppressEmpty' => true })
  end

  def respond_with_raw(response)
    response.body
  end


  def to_uri(url)
    begin
      if !url.kind_of?(URI)
        url = URI.parse(url)
      end
    rescue
      raise URI::InvalidURIError, "Invalid url '#{url}'"
    end

    if (url.class != URI::HTTP && url.class != URI::HTTPS)
      raise URI::InvalidURIError, "Invalid url '#{url}'"
    end

    url
  end

  def execute(url, options = {})
    options = {
      :parameters     => {:api_key => API_KEY},
      :debug          => true,
      :http_timeout   => 60,
      :headers        => {},
      :redirect_count => 0,
      :max_redirects  => 10,
      :content_type   => options[:content_type].blank? ? "text/xml" : options[:content_type]
    }.merge(options)

    url = to_uri(url)
    http = Net::HTTP.new(url.host, url.port)

    if url.scheme == 'https'
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end

    http.open_timeout = http.read_timeout = options[:http_timeout]

    http.set_debug_output $stderr if options[:debug]

    request = case options[:method]
      when :post
        request = Net::HTTP::Post.new(url.request_uri)
      when :put
        request = Net::HTTP::Put.new(url.request_uri)
      when :delete
        request = Net::HTTP::Delete.new(url.request_uri)
      else
        Net::HTTP::Get.new(url.request_uri)
    end
    request.body = options[:body]
    request

    request.content_type = options[:content_type] if options[:content_type]

    options[:headers].each { |key, value| request[key] = value }
    response = http.request(request)

    if response.kind_of?(Net::HTTPRedirection)      
      options[:redirect_count] += 1

      if options[:redirect_count] > options[:max_redirects]
        raise "Too many redirects (#{options[:redirect_count]}): #{url}" 
      end

      redirect_url = redirect_url(response)

      if redirect_url.start_with?('/')
        url = to_uri("#{url.scheme}://#{url.host}#{redirect_url}")
      end

      response = execute(url, options)
    end

    #response.to_yaml
    response
  end

  # From http://railstips.org/blog/archives/2009/03/04/following-redirects-with-nethttp/
  def redirect_url(response)
    if response['location'].nil?
      response.body.match(/<a href=\"([^>]+)\">/i)[1]
    else
      response['location']
    end
  end

  def assemble_xml(data, request_type)
    case request_type
    when 'new_customer'
      #
      #  Per the Yext API - creates customer, location, and subscription in one request
      #
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.customer {
          xml.id                data.yext_customer_id
          xml.businessName      data.business_name
          xml.contactFirstName  data.contact_first_name
          xml.contactLastName   data.contact_last_name
          xml.contactPhone      data.contact_phone
          xml.contactEmail      data.contact_email
          xml.locations {
            data.business_locations.all.each do |l|
              xml.location {
                xml.id            l.yext_location_id
                xml.locationName  l.location_name
                xml.address       l.address
                xml.address2      l.address_2
                xml.city          l.city
                xml.state         l.state
                xml.zip           l.zip
                xml.phone         l.phone
                xml.description   l.description
                xml.localPhone    l.local_phone
                xml.websiteUrl    l.website_url
                xml.hours         l.hours
                xml.specialOffer  l.special_offer
                unless l.logo.blank?
                  xml.logo {
                   xml.url          l.logo
                   xml.description  l.location_name
                  }
                end
                unless l.photo.blank?
                  xml.photos {
                    xml.photo {
                      xml.url          l.photo
                      xml.description  l.location_name
                    }
                  }
                end
                xml.categoryIds {
                  l.category_ids.delete_if{|x| x.blank?}.each do |c|
                    xml.categoryId  c
                  end
                }
              }
            end
          }
          xml.subscriptions {
            xml.subscription {
              xml.offerId  YEXT_OFFER_ID # hard coded Yext offer
              xml.locationIds {
                xml.locationId  data.business_locations.first.yext_location_id
              }
            }
          }
        }
      end

    when 'customer'
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.customer {
          xml.id                data.yext_customer_id
          xml.businessName      data.business_name
          xml.contactFirstName  data.contact_first_name
          xml.contactLastName   data.contact_last_name
          xml.contactPhone      data.contact_phone
          xml.contactEmail      data.contact_email
        }
      end

    when 'location'
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.location {
          xml.id            data.yext_location_id
          xml.locationName  data.location_name
          xml.address       data.address
          xml.address2      data.address_2
          xml.city          data.city
          xml.state         data.state
          xml.zip           data.zip
          xml.phone         data.phone
          xml.description   data.description
          xml.localPhone    data.local_phone
          xml.websiteUrl    data.website_url
          xml.hours         data.hours
          xml.specialOffer  data.special_offer
          unless data.logo.blank?
            xml.logo {
             xml.url          data.logo
             xml.description  data.location_name
            }
          end
          unless data.photo.blank?
            xml.photos {
              xml.photo {
                xml.url          data.photo
                xml.description  data.location_name
              }
            }
          end
          xml.categoryIds {
            data.category_ids.delete_if{|x| x.blank?}.each do |c|
              xml.categoryId  c
            end
          }
        }
      end

    when 'cancel_subscription'
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.subscription {
          xml.status    "CANCELED"
        }
      end

    end

    xml = builder.to_xml

    # print to console so we can see whats going on
    puts "-------------------------"
    puts xml
    puts "-------------------------"

    xml_as_string = xml

  end

end
