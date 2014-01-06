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

# Make sure we use the admin node for now.
my_ipaddress = node.address.addr
node[:glance][:api][:bind_host] = my_ipaddress
node[:glance][:registry][:bind_host] = my_ipaddress

env_filter = " AND database_config_environment:database-config-#{node[:glance][:database_instance]}"
sqls = search(:node, "roles:database-server#{env_filter}") || []
if sqls.length > 0
  sql = sqls[0]
  sql = node if sql.name == node.name
else
  sql = node
end
include_recipe "database::client"
backend_name = Chef::Recipe::Database::Util.get_backend_name(sql)
include_recipe "#{backend_name}::client"
include_recipe "#{backend_name}::python-client"

db_provider = Chef::Recipe::Database::Util.get_database_provider(sql)
db_user_provider = Chef::Recipe::Database::Util.get_user_provider(sql)
privs = Chef::Recipe::Database::Util.get_default_priviledges(sql)
url_scheme = backend_name

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)

node.set_unless['glance']['db']['password'] = secure_password
node.set_unless['glance']['db']['user'] = "glance"
node.set_unless['glance']['db']['database'] = "glancedb"

sql_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(sql, "admin").address if sql_address.nil?
Chef::Log.info("Database server found at #{sql_address}")

db_conn = { :host => sql_address,
          :username => "db_maker",
          :password => sql[:database][:db_maker_password] }

# Create the Glance Database
database "create #{node[:glance][:db][:database]} database" do
  connection db_conn
  database_name node[:glance][:db][:database]
  provider db_provider
  action :create
end

database_user "create glance database user" do
  host '%'
  connection db_conn
  username node[:glance][:db][:user]
  password node[:glance][:db][:password]
  provider db_user_provider
  action :create
end

database_user "grant database access for glance database user" do
  connection db_conn
  username node[:glance][:db][:user]
  password node[:glance][:db][:password]
  database_name node[:glance][:db][:database]
  host '%'
  privileges privs
  provider db_user_provider
  action :grant
end

node[:glance][:sql_connection] = "#{url_scheme}://#{node[:glance][:db][:user]}:#{node[:glance][:db][:password]}@#{sql_address}/#{node[:glance][:db][:database]}"

node.save

# Register glance service user

if node[:glance][:use_keystone]
  env_filter = " AND keystone_config_environment:keystone-config-#{node[:glance][:keystone_instance]}"
  keystones = search(:node, "recipes:keystone\\:\\:server#{env_filter}") || []
  if keystones.length > 0
    keystone = keystones[0]
    keystone = node if keystone.name == node.name
  else
    keystone = node
  end

  keystone_host = keystone[:fqdn]
  keystone_protocol = keystone["keystone"]["api"]["protocol"]
  keystone_token = keystone["keystone"]["service"]["token"]
  keystone_admin_port = keystone["keystone"]["api"]["admin_port"]
  keystone_service_tenant = keystone["keystone"]["service"]["tenant"]
  keystone_service_user = node[:glance][:service_user]
  keystone_service_password = node[:glance][:service_password]
  Chef::Log.info("Keystone server found at #{keystone_host}")

  keystone_register "glance wakeup keystone" do
    protocol keystone_protocol
    host keystone_host
    port keystone_admin_port
    token keystone_token
    action :wakeup
  end

  keystone_register "register glance user" do
    protocol keystone_protocol
    host keystone_host
    port keystone_admin_port
    token keystone_token
    user_name keystone_service_user
    user_password keystone_service_password
    tenant_name keystone_service_tenant
    action :add_user
  end

  keystone_register "give glance user access" do
    protocol keystone_protocol
    host keystone_host
    port keystone_admin_port
    token keystone_token
    user_name keystone_service_user
    tenant_name keystone_service_tenant
    role_name "admin"
    action :add_access
  end
end
