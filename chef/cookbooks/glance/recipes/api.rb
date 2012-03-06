#
# Cookbook Name:: glance
# Recipe:: api
#
#

include_recipe "#{@cookbook_name}::common"


if node[:glance][:use_keystone]
  env_filter = " AND keystone_config_environment:keystone-config-#{node[:glance][:keystone_instance]}"
  keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
  if keystones.length > 0
    keystone = keystones[0]
    keystone = node if keystone.name == node.name
  else
    keystone = node
  end

  keystone_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(keystone, "admin").address if keystone_address.nil?
  keystone_token = keystone["keystone"]["service"]["token"]
  keystone_service_port = keystone["keystone"]["api"]["service_port"]
  keystone_admin_port = keystone["keystone"]["api"]["admin_port"]
  keystone_service_tenant = keystone["keystone"]["service"]["tenant"]
  keystone_service_user = node[:glance][:service_user]
  keystone_service_password = node[:glance][:service_password]
  Chef::Log.info("Keystone server found at #{keystone_address}")
else
  keystone_address = ""
  keystone_token = ""
end

template node[:glance][:api][:config_file] do
  source "glance-api.conf.erb"
  owner node[:glance][:user]
  group "root"
  mode 0644
end

template node[:glance][:api][:paste_ini] do
  source "glance-api-paste.ini.erb"
  owner node[:glance][:user]
  group "root"
  mode 0644
  variables(
    :keystone_address => keystone_address,
    :keystone_auth_token => keystone_token,
    :keystone_service_port => keystone_service_port,
    :keystone_service_user => keystone_service_user,
    :keystone_service_password => keystone_service_password,
    :keystone_service_tenant => keystone_service_tenant,
    :keystone_admin_port => keystone_admin_port
  )
end

if node[:glance][:use_keystone]
  my_admin_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
  my_public_ip = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "public").address
  api_port = node["glance"]["api"]["bind_port"]

  keystone_register "register glance service" do
    host keystone_address
    port keystone_admin_port
    token keystone_token
    service_name "glance"
    service_type "image"
    service_description "Openstack Glance Service"
    action :add_service
  end

  keystone_register "register glance endpoint" do
    host keystone_address
    port keystone_admin_port
    token keystone_token
    endpoint_service "glance"
    endpoint_region "RegionOne"
    endpoint_adminURL "http://#{my_admin_ip}:#{api_port}/v1"
    endpoint_internalURL "http://#{my_admin_ip}:#{api_port}/v1"
    endpoint_publicURL "http://#{my_public_ip}:#{api_port}/v1"
#  endpoint_global true
#  endpoint_enabled true
    action :add_endpoint_template
  end
end

glance_service "api"

node[:glance][:monitor][:svcs] <<["glance-api"]

