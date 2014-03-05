# Copyright 2014 SUSE
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

unless node[:glance][:ha][:enabled]
  log "HA support for glance is not enabled"
  return
end

log "Setting up glance HA support"

def ha_servers_for_service(name, component, ports_key)
  # Fetch configured HA proxy servers for a given service
  haproxy_servers, haproxy_server_nodes = PacemakerHelper.haproxy_servers(node, component)

  # Look up and store where they are listening
  haproxy_servers.each do |server|
    server_node = haproxy_server_nodes[server['name']]

    server['address'] = Chef::Recipe::Barclamp::Inventory.get_network_by_type(server_node, "admin").address
    server['port']    = server_node[name.to_sym][:ha][:ports][ports_key.to_sym]
  end

  haproxy_servers
end

haproxy_loadbalancer "glance-api" do
  address node[:glance][:api][:bind_open_address] ? "0.0.0.0" : node[:glance][:api][:bind_host]
  port    node[:glance][:api][:bind_port]
  use_ssl (node[:glance][:api][:protocol] == "https")
  servers ha_servers_for_service("glance", "glance-server", "api")
  action  :nothing
end.run_action(:create)

haproxy_loadbalancer "glance-registry" do
  address node[:glance][:registry][:bind_host]
  port    node[:glance][:registry][:bind_port]
  use_ssl false
  servers ha_servers_for_service("glance", "glance-server", "registry")
  action  :nothing
end.run_action(:create)
