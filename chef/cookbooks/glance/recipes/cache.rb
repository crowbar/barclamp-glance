#
# Cookbook Name:: glance
# Recipe:: cache
#
# Copyright 2011 Opscode, Inc.
# Copyright 2011 Rackspace, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# ensure the image_cache_datadir gets created
directory node[:glance][:image_cache_datadir] do
  owner node[:glance][:user]
  group "root"
  mode 0755
  action :create
end

keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

#TODO: glance should depend on cinder, but cinder already depends on glance :/
# so we have to do something like this
cinder_api_insecure = false
cinders = search(:node, "roles:cinder-controller") || []
if cinders.length > 0
  cinder = cinders[0]
  cinder_api_insecure = cinder[:cinder][:api][:protocol] == 'https' && cinder[:cinder][:ssl][:insecure]
end

glance_stores = node.default[:glance][:glance_stores]
glance_stores += ["glance.store.vmware_datastore.Store"] unless node[:glance][:vsphere][:host].empty?

template node[:glance][:cache][:config_file] do
  source "glance-cache.conf.erb"
  owner "root"
  group node[:glance][:group]
  mode 0640
  variables(
      :keystone_settings => keystone_settings,
      :cinder_api_insecure => cinder_api_insecure,
      :glance_stores => glance_stores.join(",")
  )
end

directory "#{node[:glance][:image_cache_datadir]}/prefetching" do
  owner node[:glance][:user]
  group "root"
  mode 0755
  action :create
end

directory "#{node[:glance][:image_cache_datadir]}/prefetch" do
  owner node[:glance][:user]
  group "root"
  mode 0755
  action :create
end

directory "#{node[:glance][:image_cache_datadir]}/invalid" do
  owner node[:glance][:user]
  group "root"
  mode 0755
  action :create
end

if node[:glance][:enable_caching]
  template "/etc/cron.d/glance-pruner" do
    source "glance.cron.erb"
    owner "root"
    group "root"
    mode 0644
    variables(
      :glance_min => "45",
      :glance_hour => "*",
      :glance_user => node[:glance][:user],
      :glance_command => "/usr/bin/glance-cache-pruner")
  end

  template "/etc/cron.d/glance-prefetcher" do
    source "glance.cron.erb"
    owner "root"
    group "root"
    mode 0644
    variables(
      :glance_min => "25",
      :glance_hour => "*",
      :glance_user => node[:glance][:user],
      :glance_command => "/usr/bin/glance-cache-prefetcher")
  end
else
  file "/etc/cron.d/glance-pruner" do
    action :delete
  end

  file "/etc/cron.d/glance-prefetcher" do
    action :delete
  end
end

