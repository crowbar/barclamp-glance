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
  package_name "openstack-glance" if node.platform == "suse"
  options "--force-yes" if node.platform != "suse"
  action :install
end

# Make sure we use the admin node for now.
my_ipaddress = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
node[:glance][:api][:bind_host] = my_ipaddress
node[:glance][:registry][:bind_host] = my_ipaddress

database = node[:glance][:database]
db_provider = nil
db_user_provider = nil
privs = nil

Chef::Log.info("Configuring Glance to use #{database} backend")

if database == "mysql"
  package "python-mysqldb" do
      package_name "python-mysql" if node.platform == "suse"
      action :install
  end
  db_provider = Chef::Provider::Database::Mysql
  db_user_provider = Chef::Provider::Database::MysqlUser
  privs = [ "SELECT", "INSERT", "UPDATE", "DELETE", "CREATE",
            "DROP", "INDEX", "ALTER" ]
elsif database == "postgresql"
  package "python-psycopg2" do
    action :install
  end
  db_provider = Chef::Provider::Database::Postgresql
  db_user_provider = Chef::Provider::Database::PostgresqlUser
  privs = [ "CREATE", "CONNECT", "TEMP" ]
end

if database == "sqlite"
  node[:glance][:sql_connection] = node[:glance][:sqlite_connection]
else
  include_recipe "#{database}::client"
  ::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)

  node.set_unless['glance']['db']['password'] = secure_password
  node.set_unless['glance']['db']['user'] = "glance"
  node.set_unless['glance']['db']['database'] = "glancedb"

  env_filter = " AND #{database}_config_environment:#{database}-config-#{node[:glance][:sql_instance]}"
  sqls = search(:node, "recipes:#{database}\\:\\:server#{env_filter}") || []
  if sqls.length > 0
    sql = sqls[0]
    sql = node if sql.name == node.name
  else
    sql = node
  end

  sql_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(sql, "admin").address if sql_address.nil?
  Chef::Log.info("#{database} server found at #{sql_address}")

  db_conn = { :host => sql_address,
              :username => "db_maker",
              :password => sql[database][:db_maker_password] }

  # Create the Glance Database
  database "create #{node[:glance][:db][:database]} database" do
    connection db_conn
    database_name node[:glance][:db][:database]
    provider db_provider
    action :create
  end

  database_user "create glance database user" do
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
    host sql_address
    privileges privs
    provider db_user_provider
    action :grant
  end

  node[:glance][:sql_connection] = "#{database}://#{node[:glance][:db][:user]}:#{node[:glance][:db][:password]}@#{sql_address}/#{node[:glance][:db][:database]}"

  file "/var/lib/glance/glance.sqlite" do
    action :delete
  end
end

bash "Set glance version control" do
  code "exit 0"
  notifies :run, "bash[Sync glance db]", :immediately
  only_if "glance-manage version_control 0"
  action :run
end

bash "Sync glance db" do
  code "glance-manage db_sync"
  action :nothing
end

node.save

