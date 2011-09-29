#
# Cookbook Name:: glance
# Recipe:: registry
#
#

include_recipe "#{@cookbook_name}::common"

template "/etc/glance/glance-registry.conf" do
  source "glance-registry.conf.erb"
  owner node[:glance][:user]
  group "root"
  mode 0644
end

glance_service "registry"

node[:glance][:monitor][:svcs] << ["glance-registry"]
