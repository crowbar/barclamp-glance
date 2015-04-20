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

  ceph_conf = "/etc/ceph/ceph.conf"
  admin_keyring = "/etc/ceph/ceph.client.admin.keyring"
  # Ensure that the ceph config file that will be written in the glance config
  # file is the right one
  node.default[:glance][:rbd][:store_ceph_conf] = ceph_conf
else
  ceph_conf = node[:glance][:rbd][:store_ceph_conf]
  admin_keyring = node[:glance][:rbd][:store_admin_keyring]

  # If Ceph configuration file is present, external Ceph cluster will be used,
  # we have to install ceph client packages
  return if (ceph_conf.empty? || !File.exists?(ceph_conf))

  if node[:platform] == "suse"
    # install package in compile phase because we will run "ceph -s"
    package "ceph-common" do
      action :nothing
    end.run_action(:install)
  end

  if !admin_keyring.empty? && File.exists?(admin_keyring)
    Chef::Log.info("Using external ceph cluster for glance, with automatic setup.")
  else
    Chef::Log.info("Using external ceph cluster for glance, with no automatic setup.")
    return
  end

  # If ceph.conf and admin keyring will be available
  # we have to check ceph cluster status
  cmd = ["ceph", "-k", admin_keyring, "-c", ceph_conf, "-s"]
  check_ceph = Mixlib::ShellOut.new(cmd)

  unless check_ceph.run_command.stdout.match("(HEALTH_OK|HEALTH_WARN)")
    Chef::Log.info("Ceph cluster is not healthy, skipping the ceph setup for glance")
    return
  end
end

ceph_user = node[:glance][:rbd][:store_user]
ceph_pool = node[:glance][:rbd][:store_pool]

ceph_caps = { 'mon' => 'allow r', 'osd' => "allow class-read object_prefix rbd_children, allow rwx pool=#{ceph_pool}" }

ceph_client ceph_user do
  ceph_conf ceph_conf
  admin_keyring admin_keyring
  caps ceph_caps
  keyname "client.#{ceph_user}"
  filename "/etc/ceph/ceph.client.#{ceph_user}.keyring"
  owner "root"
  group node[:glance][:group]
  mode 0640
end

ceph_pool ceph_pool do
  ceph_conf ceph_conf
  admin_keyring admin_keyring
end
