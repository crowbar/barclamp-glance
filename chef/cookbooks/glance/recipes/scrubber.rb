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
  Chef::Log.info("Keystone server found at #{keystone_address}")
else
  keystone_address = ""
  keystone_token = ""
end

template node[:glance][:scrubber][:config_file] do
  source "glance-scrubber.conf.erb"
  owner node[:glance][:user]
  group "root"
  mode 0600
  variables(
    :keystone_address => keystone_address,
    :keystone_admin_token => keystone_token
  )
end

template "/etc/cron.d/glance-scrubber" do
  source "glance.cron.erb"
  owner "root"
  group "root"
  mode 0644
  variables(
    :glance_min => "1",
    :glance_hour => "*",
    :glance_command => "/usr/bin/glance-scrubber")
end

