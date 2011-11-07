#
# Cookbook Name:: glance
# Recipe:: registry
#
#

include_recipe "#{@cookbook_name}::common"

if node[:glance][:use_keystone]
  env_filter = " AND keystone_config_environment:keystone-config-#{node[:glance][:keystone_instance]}"
  keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
  if keystones.length > 0
    keystone = keystones[0]
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

template node[:glance][:registry][:config_file] do
  source "glance-registry.conf.erb"
  owner node[:glance][:user]
  group "root"
  mode 0644
  variables(
    :keystone_address => keystone_address,
    :keystone_auth_token => keystone[:keystone][:admin]['token']
  )
end

glance_service "registry"

node[:glance][:monitor][:svcs] << ["glance-registry"]
