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
  keystone_token = keystone[:keystone][:admin]['token']
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
    :keystone_auth_token => keystone_token
  )
end

glance_service "api"

my_ipaddress = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
port = node["glance"]["api"]["bind_port"]

keystone_register "register glance service" do
  host keystone_address
  token node[:keystone][:admin][:token]
  service_name "glance"
  service_description "Openstack Glance Service"
  action :add_service
end

keystone_register "register glance endpoint" do
  host keystone_address
  token node[:keystone][:admin][:token]
  endpoint_service "glance"
  endpoint_region "RegionOne"
  endpoint_adminURL "http://#{my_ipaddress}:#{port}/v1.1"
  endpoint_internalURL "http://#{my_ipaddress}:#{port}/v1.1"
  endpoint_publicURL "http://#{my_ipaddress}:#{port}/v1.1"
#  endpoint_global true
#  endpoint_enabled true
  action :add_endpoint_template
end

node[:glance][:monitor][:svcs] <<["glance-api"]

