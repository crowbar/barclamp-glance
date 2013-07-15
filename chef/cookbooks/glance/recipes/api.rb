#
# Cookbook Name:: glance
# Recipe:: api
#
#

include_recipe "#{@cookbook_name}::common"

glance_path = "/opt/glance"
venv_path = node[:glance][:use_virtualenv] ? "#{glance_path}/.venv" : nil
venv_prefix = node[:glance][:use_virtualenv] ? ". #{venv_path}/bin/activate &&" : nil

if node[:glance][:use_keystone]
  env_filter = " AND keystone_config_environment:keystone-config-#{node[:glance][:keystone_instance]}"
  keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
  if keystones.length > 0
    keystone = keystones.first
    keystone = node if keystone.name == node.name
  else
    keystone = node
  end

  keystone_host = keystone[:fqdn]
  keystone_protocol = keystone["keystone"]["api"]["protocol"]
  keystone_token = keystone["keystone"]["service"]["token"]
  keystone_service_port = keystone["keystone"]["api"]["service_port"]
  keystone_admin_port = keystone["keystone"]["api"]["admin_port"]
  keystone_service_tenant = keystone["keystone"]["service"]["tenant"]
  keystone_service_user = node[:glance][:service_user]
  keystone_service_password = node[:glance][:service_password]
  Chef::Log.info("Keystone server found at #{keystone_host}")
else
  keystone_protocol = ""
  keystone_host = ""
  keystone_token = ""
  keystone_service_port = ""
  keystone_service_tenant = ""
  keystone_service_user = ""
  keystone_service_password = ""
end

if node[:glance][:api][:protocol] == 'https'
  unless ::File.exists? node[:glance][:ssl][:certfile]
    message = "Certificate \"#{node[:glance][:ssl][:certfile]}\" is not present."
    Chef::Log.fatal(message)
    raise message
  end
  # we do not check for existence of keyfile, as the private key is allowed to
  # be in the certfile
  if node[:glance][:ssl][:cert_required] and !::File.exists? node[:glance][:ssl][:ca_certs]
    message = "Certificate CA \"#{node[:glance][:ssl][:ca_certs]}\" is not present."
    Chef::Log.fatal(message)
    raise message
  end
end

template node[:glance][:api][:config_file] do
  source "glance-api.conf.erb"
  owner "root"
  group node[:glance][:group]
  mode 0640
  variables(
      :keystone_protocol => keystone_protocol,
      :keystone_host => keystone_host,
      :keystone_admin_port => keystone_admin_port,
      :keystone_service_port => keystone_service_port,
      :keystone_service_user => keystone_service_user,
      :keystone_service_password => keystone_service_password,
      :keystone_service_tenant => keystone_service_tenant
  )
end

if node[:glance][:use_keystone]

  my_admin_host = node[:fqdn]
  # For the public endpoint, we prefer the public name. If not set, then we
  # use the IP address except for SSL, where we always prefer a hostname
  # (for certificate validation).
  my_public_host = node[:crowbar][:public_name]
  if my_public_host.nil? or my_public_host.empty?
    unless node[:glance][:api][:protocol] == "https"
      my_public_host = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "public").address
    else
      my_public_host = 'public.'+node[:fqdn]
    end
  end

  # If we let the service bind to all IPs, then the service is obviously usable
  # from the public network. Otherwise, the endpoint URL should use the unique
  # IP that will be listened on.
  if node[:glance][:api][:bind_open_address]
    endpoint_admin_ip = my_admin_host
    endpoint_public_ip = my_public_host
  else
    endpoint_admin_ip = node[:glance][:api][:bind_host]
    endpoint_public_ip = node[:glance][:api][:bind_host]
  end
  api_port = node["glance"]["api"]["bind_port"]
  glance_protocol = node[:glance][:api][:protocol]

  keystone_register "register glance service" do
    protocol keystone_protocol
    host keystone_host
    port keystone_admin_port
    token keystone_token
    service_name "glance"
    service_type "image"
    service_description "Openstack Glance Service"
    action :add_service
  end

  keystone_register "register glance endpoint" do
    protocol keystone_protocol
    host keystone_host
    port keystone_admin_port
    token keystone_token
    endpoint_service "glance"
    endpoint_region "RegionOne"
    endpoint_publicURL "#{glance_protocol}://#{endpoint_public_ip}:#{api_port}"
    endpoint_adminURL "#{glance_protocol}://#{endpoint_admin_ip}:#{api_port}"
    endpoint_internalURL "#{glance_protocol}://#{endpoint_admin_ip}:#{api_port}"
#  endpoint_global true
#  endpoint_enabled true
    action :add_endpoint_template
  end
end

glance_service "api"

node[:glance][:monitor][:svcs] <<["glance-api"]

