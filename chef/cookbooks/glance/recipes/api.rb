#
# Cookbook Name:: glance
# Recipe:: api
#
#

include_recipe "#{@cookbook_name}::common"

template "/etc/glance/glance-api.conf" do
  source "glance-api.conf.erb"
  owner node[:glance][:user]
  group "root"
  mode 0644
end

glance_service "api"

node[:glance][:monitor][:svcs] <<["glance-api"]

