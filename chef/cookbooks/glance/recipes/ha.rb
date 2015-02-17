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

network_settings = GlanceHelper.network_settings(node)

haproxy_loadbalancer "glance-api" do
  address network_settings[:api][:ha_bind_host]
  port    network_settings[:api][:ha_bind_port]
  use_ssl (node[:glance][:api][:protocol] == "https")
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "glance", "glance-server", "api")
  action  :nothing
end.run_action(:create)

haproxy_loadbalancer "glance-registry" do
  address network_settings[:registry][:ha_bind_host]
  port    network_settings[:registry][:ha_bind_port]
  use_ssl false
  servers CrowbarPacemakerHelper.haproxy_servers_for_service(node, "glance", "glance-server", "registry")
  action  :nothing
end.run_action(:create)

# Wait for all nodes to reach this point so we know that all nodes will have
# all the required packages installed before we create the pacemaker
# resources
crowbar_pacemaker_sync_mark "sync-glance_before_ha"

# Avoid races when creating pacemaker resources
crowbar_pacemaker_sync_mark "wait-glance_ha_resources"

primitives = []

["registry", "api"].each do |service|
  primitive_name = "glance-#{service}"

  pacemaker_primitive primitive_name do
    agent node[:glance][:ha][service.to_sym][:agent]
    op    node[:glance][:ha][service.to_sym][:op]
    action :create
    only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
  end
  primitives << primitive_name
end

group_name = "g-glance"

pacemaker_group group_name do
  members primitives
  action :create
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

pacemaker_clone "cl-#{group_name}" do
  rsc group_name
  action [ :create, :start]
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

crowbar_pacemaker_order_only_existing "o-cl-#{group_name}" do
  ordering [ "postgresql", "rabbitmq", "cl-keystone", "cl-#{group_name}" ]
  score "Optional"
  action :create
  only_if { CrowbarPacemakerHelper.is_cluster_founder?(node) }
end

crowbar_pacemaker_sync_mark "create-glance_ha_resources"
