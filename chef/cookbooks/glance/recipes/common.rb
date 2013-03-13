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

glance_path = "/opt/glance"
venv_path = node[:glance][:use_virtualenv] ? "#{glance_path}/.venv" : nil
venv_prefix = node[:glance][:use_virtualenv] ? ". #{venv_path}/bin/activate &&" : nil

package "curl" do
  action :install
end

unless node[:glance][:use_gitrepo]
  package "python-keystone" do
    action :install
  end
  package "glance" do
    package_name "openstack-glance" if node.platform == "suse"
    options "--force-yes" if node.platform != "suse"
    action :install
  end
else

  pfs_and_install_deps @cookbook_name do
    virtualenv venv_path
    wrap_bins [ "glance" ]
  end

  create_user_and_dirs("glance")
  execute "cp_.json_#{@cookbook_name}" do
    command "cp #{glance_path}/etc/*.json /etc/#{@cookbook_name}"
    creates "/etc/#{@cookbook_name}/policy.json"
  end

  link_service "glance-api" do
    virtualenv venv_path
  end

  link_service "glance-registry" do
    virtualenv venv_path
  end

end

# Make sure we use the admin node for now.
my_ipaddress = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
node[:glance][:api][:bind_host] = my_ipaddress
node[:glance][:registry][:bind_host] = my_ipaddress

if node[:glance][:database] == "mysql"
  ::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)

  node.set_unless['glance']['db']['password'] = secure_password
  node.set_unless['glance']['db']['user'] = "glance"
  node.set_unless['glance']['db']['database'] = "glancedb"

  Chef::Log.info("Configuring Glance to use MySQL backend")
  include_recipe "mysql::client"

  package "python-mysqldb" do
      action :install
  end

  env_filter = " AND mysql_config_environment:mysql-config-#{node[:glance][:mysql_instance]}"
  mysqls = search(:node, "recipes:mysql\\:\\:server#{env_filter}") || []
  if mysqls.length > 0
    mysql = mysqls[0]
    mysql = node if mysql.name == node.name
  else
    mysql = node
  end

  mysql_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(mysql, "admin").address if mysql_address.nil?
  Chef::Log.info("Mysql server found at #{mysql_address}")

  # Create the Glance Database
  mysql_database "create #{node[:glance][:db][:database]} database" do
    host    mysql_address
    username "db_maker"
    password mysql[:mysql][:db_maker_password]
    database node[:glance][:db][:database]
    action :create_db
  end

  mysql_database "create glance database user" do
    host    mysql_address
    username "db_maker"
    password mysql[:mysql][:db_maker_password]
    database node[:glance][:db][:database]
    action :query
    sql "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER on #{node[:glance][:db][:database]}.* to '#{node[:glance][:db][:user]}'@'%' IDENTIFIED BY '#{node[:glance][:db][:password]}';"
  end

  node[:glance][:sql_connection] = "mysql://#{node[:glance][:db][:user]}:#{node[:glance][:db][:password]}@#{mysql_address}/#{node[:glance][:db][:database]}"

  file "/var/lib/glance/glance.sqlite" do
    action :delete
  end
else
  node[:glance][:sql_connection] = node[:glance][:sqlite_connection]
end

node.save

