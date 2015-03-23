#
# Cookbook Name:: glance
# Recipe:: ceph
#
# Copyright (c) 2015 SUSE Linux GmbH.
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

ceph_env_filter = " AND ceph_config_environment:ceph-config-default"
ceph_servers = search(:node, "roles:ceph-osd#{ceph_env_filter}") || []
if ceph_servers.length > 0
  include_recipe "ceph::keyring"
else
  # If external Ceph cluster will be used,
  # we need install ceph client packages
  if node[:platform] == "suse" && File.exists?("/etc/ceph/ceph.client.admin.keyring")
    package "ceph-common"
    package "python-ceph"
  else 
    return
  end
end

# If ceph.conf and admin keyring will be available 
# we have to check ceph cluster status
check_ceph = Mixlib::ShellOut.new("ceph -s | grep -q -e 'HEALTH_[OK|WARN]'")
check_ceph.run_command

if check_ceph.exitstatus == 0

  ceph_user = node[:glance][:rbd][:store_user]
  ceph_pool = node[:glance][:rbd][:store_pool]

  ceph_caps = { 'mon' => 'allow r', 'osd' => "allow class-read object_prefix rbd_children, allow rwx pool=#{ceph_pool}" }

  ceph_client ceph_user do
    caps ceph_caps
    keyname "client.#{ceph_user}"
    filename "/etc/ceph/ceph.client.#{ceph_user}.keyring"
    owner "root"
    group node[:glance][:group]
    mode 0640
  end

  ceph_pool ceph_pool

end
