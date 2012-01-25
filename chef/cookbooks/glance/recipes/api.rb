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
  keystone_token = keystone["keystone"]["admin"]["token"]
  keystone_service_port = keystone["keystone"]["api"]["service_port"]
  keystone_admin_port = keystone["keystone"]["api"]["admin_port"]
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
  variables(
    :keystone_address => keystone_address,
    :keystone_auth_token => keystone_token,
    :keystone_service_port => keystone_service_port,
    :keystone_admin_port => keystone_admin_port
  )
end

glance_service "api"

if node[:glance][:use_keystone]
  my_ipaddress = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
  port = node["glance"]["api"]["bind_port"]

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
    endpoint_adminURL "http://#{my_ipaddress}:#{port}/v1"
    endpoint_internalURL "http://#{my_ipaddress}:#{port}/v1"
    endpoint_publicURL "http://#{my_ipaddress}:#{port}/v1"
#  endpoint_global true
#  endpoint_enabled true
    action :add_endpoint_template
  end
end

node[:glance][:monitor][:svcs] <<["glance-api"]

