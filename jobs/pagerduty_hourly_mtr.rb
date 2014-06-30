require 'faraday'
require 'json'
require 'chronic'

secrets_file = './lib/secrets.json'
secrets_data = JSON.parse( IO.read( secrets_file ))

@url = secrets_data['url']
@api_key = secrets_data['api_key']

@hourly_resolution_times = []
@hourly_total_incidents = 0

# Call the PagerDuty API and get the incidents
def hourly_pd_query(offset)
  hour = Time.now.strftime("%H")
  conn = Faraday.new(:url => "#{@url}") do |faraday|
    faraday.request :url_encoded
    faraday.adapter Faraday.default_adapter
    faraday.headers['Content-type'] = 'application/json'
    faraday.headers['Authorization'] = "Token token=#{@api_key}"
    faraday.params['since'] = Chronic.parse("today at #{hour}:00:00")
    faraday.params['until'] = Chronic.parse('now')
    faraday.params['offset'] = offset
    faraday.params['limit'] = 50
    faraday.params['status'] = 'resolved'
  end

  response = conn.get '/api/v1/incidents/'

  if response.status == 200
    data = JSON.parse(response.body)
    @hourly_total_incidents = data['total']
  else
    data['total'] == 0
  end
  return data
end

# Caclulate the mtr (mean time to resolution) and format it
def calc_hourly_mtr()
  if @hourly_resolution_times.size == 0
    mtr = 0
    return mtr
  else
    mtr = @hourly_resolution_times.inject{ |sum, el| sum + el }.to_f / @hourly_resolution_times.size rescue 0
    mtr = (mtr / 60).round(3)
    return mtr
  end
end

SCHEDULER.every '60s' do

  while @hourly_resolution_times.length <= @hourly_total_incidents do

    # We're just starting out, first query to PagerDuty
    if @hourly_resolution_times.length == 0
      offset = 0
    # We have all of the incidents, stop querying
    elsif @hourly_resolution_times.length == @hourly_total_incidents
      break
    # We don't have all of the incidents, increment the offset and query again
    else
      offset += 50
    end
    
    # Call the PagerDuty API with the appropriate parameters and offset
    data = hourly_pd_query(offset)

    if data['total'] == 0
      break
    end

    data['incidents'].each do |item|
      incident_number = item['incident_number']
      created_on = Time.parse(item['created_on'])
      resolved_on = Time.parse(item['last_status_change_on'])
      time_open = resolved_on - created_on
      
      @hourly_resolution_times.push(time_open)
    end
  end

  hourly_mtr = calc_hourly_mtr()
  send_event('hourly_incidents_mtr', { value: hourly_mtr})

end