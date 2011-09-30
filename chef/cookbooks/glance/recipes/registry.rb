#
# Cookbook Name:: glance
# Recipe:: registry
#
#

include_recipe "#{@cookbook_name}::common"

template node[:glance][:registry][:config_file] do
  source "glance-registry.conf.erb"
  owner node[:glance][:user]
  group "root"
  mode 0644
end

glance_service "registry"

node[:glance][:monitor][:svcs] << ["glance-registry"]
