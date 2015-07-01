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

network_settings = GlanceHelper.network_settings(node)

keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

template node[:glance][:scrubber][:config_file] do
  source "glance-scrubber.conf.erb"
  owner "root"
  group node[:glance][:group]
  mode 0640
  variables(
    :registry_bind_host => network_settings[:registry][:bind_host],
    :registry_bind_port => network_settings[:registry][:bind_port],
    :keystone_settings => keystone_settings
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
    :glance_user => node[:glance][:user],
    :glance_command => "/usr/bin/glance-scrubber "\
                       "--config-dir #{node[:glance][:config_dir]}")
end

