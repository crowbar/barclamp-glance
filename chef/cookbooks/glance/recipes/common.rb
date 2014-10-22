#
# Cookbook Name:: glance
# Recipe:: common
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

package "curl" do
  action :install
end

unless node[:glance][:use_gitrepo]
  package "glance" do
    package_name "openstack-glance" if %w(redhat centos suse).include?(node.platform)
    options "--force-yes" if %w(debian ubuntu).include?(node.platform)
    action :install
  end
else
  glance_path = "/opt/glance"
  venv_path = node[:glance][:use_virtualenv] ? "#{glance_path}/.venv" : nil
  venv_prefix = node[:glance][:use_virtualenv] ? ". #{venv_path}/bin/activate &&" : nil

  pfs_and_install_deps @cookbook_name do
    virtualenv venv_path
    wrap_bins [ "glance" ]
  end

  create_user_and_dirs("glance")
  execute "cp_.json_#{@cookbook_name}" do
    command "cp #{glance_path}/etc/*.json /etc/#{@cookbook_name}"
    creates "/etc/#{@cookbook_name}/policy.json"
  end
  execute "cp_paste-ini_#{@cookbook_name}" do
    command "cp #{glance_path}/etc/glance-*-paste.ini /etc/#{@cookbook_name}"
    creates "/etc/#{@cookbook_name}/glance-api-paste.ini"
  end

  link_service "glance-api" do
    virtualenv venv_path
  end

  link_service "glance-registry" do
    virtualenv venv_path
  end

end

db_settings = fetch_database_settings
include_recipe "database::client"
include_recipe "#{db_settings[:backend_name]}::client"
include_recipe "#{db_settings[:backend_name]}::python-client"

crowbar_pacemaker_sync_mark "wait-glance_database"

# Create the Glance Database
database "create #{node[:glance][:db][:database]} database" do
  connection db_settings[:connection]
  database_name node[:glance][:db][:database]
  provider db_settings[:provider]
  action :create
end

database_user "create glance database user" do
  host '%'
  connection db_settings[:connection]
  username node[:glance][:db][:user]
  password node[:glance][:db][:password]
  provider db_settings[:user_provider]
  action :create
end

database_user "grant database access for glance database user" do
  connection db_settings[:connection]
  username node[:glance][:db][:user]
  password node[:glance][:db][:password]
  database_name node[:glance][:db][:database]
  host '%'
  privileges db_settings[:privs]
  provider db_settings[:user_provider]
  action :grant
end

crowbar_pacemaker_sync_mark "create-glance_database"

node[:glance][:sql_connection] = "#{db_settings[:url_scheme]}://#{node[:glance][:db][:user]}:#{node[:glance][:db][:password]}@#{db_settings[:address]}/#{node[:glance][:db][:database]}"

node.save

# Register glance service user

keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

crowbar_pacemaker_sync_mark "wait-glance_register_user"

keystone_register "glance wakeup keystone" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  action :wakeup
end

keystone_register "register glance user" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  user_name keystone_settings['service_user']
  user_password keystone_settings['service_password']
  tenant_name keystone_settings['service_tenant']
  action :add_user
end

keystone_register "give glance user access" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  user_name keystone_settings['service_user']
  tenant_name keystone_settings['service_tenant']
  role_name "admin"
  action :add_access
end

crowbar_pacemaker_sync_mark "create-glance_register_user"

# Check if right default_store was selected
if node['glance']['default_store'] == 'rbd'
  ceph_env_filter = " AND ceph_config_environment:ceph-config-default"
  ceph_servers = search(:node, "roles:ceph-osd#{ceph_env_filter}") || []
  if ceph_servers.length > 0
    include_recipe "ceph::glance"
  end
end
