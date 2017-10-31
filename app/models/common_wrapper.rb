# frozen_string_literal: true
class CommonWrapper
  attr_accessor :api_key

  def initialize(api_key)
    @api_key = api_key
  end

  def services_endpoint
    @services_endpoint ||= {
      community_service: CatarseSettings[:common_community_service_api],
      project_service: CatarseSettings[:common_project_service_api],
      payment_service: CatarseSettings[:common_payment_service_api]
    }
  end

  def find_project(external_id)
    response = request(
      "#{services_endpoint[:project_service]}/projects",
      params: {
        "external_id::integer" => "eq.#{external_id}"
      },
      action: :get,
      headers: { 'Accept' => 'application/vnd.pgrst.object+json' },
    ).run

    if response.success?
      json = ActiveSupport::JSON.decode(response.body)
      common_id = json.try(:[], 'id')
      return common_id
    end

    return
  end

  def find_user(external_id)
    response = request(
      "#{services_endpoint[:community_service]}/users",
      params: {
        "external_id::integer" => "eq.#{external_id}"
      },
      action: :get,
      headers: { 'Accept' => 'application/vnd.pgrst.object+json' },
    ).run

    if response.success?
      json = ActiveSupport::JSON.decode(response.body)
      common_id = json.try(:[], 'id')
      return common_id
    end

    return
  end

  def index_user(resource)
    response = request(
      "#{services_endpoint[:community_service]}/rpc/user",
      body: {
        data: resource.common_index.to_json
      }.to_json,
      action: :post,
      current_ip: resource.current_sign_in_ip
    ).run

    if response.success?
      json = ActiveSupport::JSON.decode(response.body)
      common_id = json.try(:[], 'id')
    else
      common_id = find_user(resource.id)
    end

    resource.update_column(:common_id,
                           common_id.presence || resource.common_id)
    return common_id;
  end

  def index_project(resource)
    unless resource.user.common_id.present?
      resource.user.index_on_common
      resource.user.reload
    end
    response = request(
      "#{services_endpoint[:project_service]}/rpc/project",
      body: {
        data: resource.common_index.to_json
      }.to_json,
      action: :post,
      current_ip: resource.user.current_sign_in_ip
    ).run

    if response.success?
      json = ActiveSupport::JSON.decode(response.body)
      common_id = json.try(:[], 'id')
    else
      common_id = find_project(resource.id)
    end

    resource.update_column(
      :common_id,
      (common_id.presence || resource.common_id)
    )

    return common_id;
  end

  def base_headers(current_ip)
    h = {
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }.merge!({ 'Authorization' => "Bearer #{@api_key}" })

    if Rails.env.development?
      h.merge!({ 'X-Forwarded-For' => current_ip })
    end

    h
  end

  def request(endpoint, options = {})
    Typhoeus::Request.new(
      endpoint,
      params: options[:params] || {},
      body: options[:body] || {},
      headers: base_headers(options[:current_ip]).merge(options[:headers] || {}),
      method: options[:action] || :get
    )
  end

end
