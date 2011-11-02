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

package "python-keystone" do
  action :install
end

package "glance" do
  options "--force-yes"
  action :install
end

# Make sure we use the admin node for now.
my_ipaddress = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
node[:glance][:api][:bind_host] = my_ipaddress
node[:glance][:registry][:bind_host] = my_ipaddress

if node[:glance][:database] == "mysql"

  node.set_unless['glance']['db']['password'] = secure_password
  node.set_unless['glance']['db']['user'] = "glance"
  node.set_unless['glance']['db']['database'] = "glancedb"

  Chef::Log.info("Configuring Glance to use MySQL backend")
  include_recipe "mysql::client"

  package "python-mysqldb" do
      action :install
  end

  mysqls = search(:node, "recipes:mysql\\:\\:server") || []
  if mysqls.length > 0
    mysql = mysqls[0]
  else
    mysql = node
  end

  mysql_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(mysql, "admin").address if mysql_address.nil?
  Chef::Log.info("Mysql server found at #{mysql_address}")

  # Create the Dashboard Database
  mysql_database "create #{node[:glance][:db][:database]} database" do
    host    mysql_address
    username "db_maker"
    password mysql[:mysql][:db_maker_password]
    database node[:glance][:db][:database]
    action :create_db
  end

  mysql_database "create dashboard database user" do
    host    mysql_address
    username "db_maker"
    password mysql[:mysql][:db_maker_password]
    database node[:dashboard][:db][:database]
    action :query
    sql "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER on #{node[:dashboard][:db][:database]}.* to '#{node[:dashboard][:db][:user]}'@'%' IDENTIFIED BY '#{node[:dashboard][:db][:password]}';"
  end

  node[:glance][:sql_connection] = "mysql://#{node[:glance][:db][:user]}:#{node[:glance][:db][:password]}@#{mysql_address}/#{node[:glance][:db][:database]}"

  file "/var/lib/glance/glance.sqlite" do
    action :delete
  end
else
  node[:glance][:sql_connection] = node[:glance][:sqlite_connection]
end

node.save

