# -*- encoding : utf-8 -*-
#
# Copyright 2011-2013, Dell
# Copyright 2013-2014, SUSE LINUX Products GmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class GlanceService < PacemakerServiceObject
  def initialize(thelogger)
    super(thelogger)
    @bc_name = "glance"
  end

  def self.allow_multiple_proposals?
    false
  end

  class << self
    def role_constraints
      {
        "glance-server" => {
          "unique" => false,
          "cluster" => true,
          "count" => 1
        }
      }
    end
  end

  def proposal_dependencies(role)
    answer = []
    answer << { "barclamp" => "database", "inst" => role.default_attributes["glance"]["database_instance"] }
    if role.default_attributes["glance"]["notifier_strategy"] == "rabbit"
      answer << { "barclamp" => "rabbitmq", "inst" => role.default_attributes["glance"]["rabbitmq_instance"] }
    end
    answer << { "barclamp" => "keystone", "inst" => role.default_attributes["glance"]["keystone_instance"] }
    if role.default_attributes[@bc_name]["use_gitrepo"]
      answer << { "barclamp" => "git", "inst" => role.default_attributes[@bc_name]["git_instance"] }
    end
    answer
  end

  def create_proposal
    @logger.debug("Glance create_proposal: entering")
    base = super

    nodes = NodeObject.all
    nodes.delete_if { |n| n.nil? or n.admin? }
    if nodes.size >= 1
      controller = nodes.find { |n| n.intended_role == "controller" } || nodes.first
      base["deployment"]["glance"]["elements"] = {
        "glance-server" => [ controller[:fqdn] ]
      }
    end

    base["attributes"][@bc_name]["git_instance"] = find_dep_proposal("git", true)
    base["attributes"][@bc_name]["database_instance"] = find_dep_proposal("database")
    base["attributes"][@bc_name]["rabbitmq_instance"] = find_dep_proposal("rabbitmq", true)
    base["attributes"][@bc_name]["keystone_instance"] = find_dep_proposal("keystone")

    if base["attributes"][@bc_name]["rabbitmq_instance"].blank?
      base["attributes"]["glance"]["notifier_strategy"] = "noop"
    else
      base["attributes"]["glance"]["notifier_strategy"] = "rabbit"
    end

    base["attributes"]["glance"]["service_password"] = '%012d' % rand(1e12)
    base["attributes"][@bc_name][:db][:password] = random_password

    @logger.debug("Glance create_proposal: exiting")
    base
  end

  def validate_proposal_after_save proposal
    validate_one_for_role proposal, "glance-server"

    if proposal["attributes"][@bc_name]["use_gitrepo"]
      validate_dep_proposal_is_active "git", proposal["attributes"][@bc_name]["git_instance"]
    end

    super
  end


  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Glance apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    # Role can be assigned to clusters, so we need to expand the elements to get the actual list of nodes.
    server_elements, server_nodes, has_expanded = role_expand_elements(role, "glance-server")

    # If glance_elements != glance_nodes, has_expanded will be true, which currently means we want to use HA.
    ha_enabled = has_expanded

    # FIXME: this deserves a comment
    if role.default_attributes["glance"]["api"]["bind_open_address"]
      vip_networks = ["admin", "public"]
    else
      vip_networks = ["admin"]
    end

    # Mark HA as enabled and initialize HA and networks in the role's pacemaker attribute
    prepare_role_for_ha_with_haproxy(role, ["glance", "ha", "enabled"], ha_enabled, server_elements, vip_networks) && role.save

    # Update images paths
    nodes = NodeObject.find("roles:provisioner-server")
    unless nodes.nil? or nodes.length < 1
      admin_ip = nodes[0].get_network_by_type("admin")["address"]
      web_port = nodes[0]["provisioner"]["web_port"]
      # substitute the admin web portal
      new_array = []
      role.default_attributes["glance"]["images"].each do |item|
        new_array << item.gsub("|ADMINWEB|", "#{admin_ip}:#{web_port}")
      end
      role.default_attributes["glance"]["images"] = new_array
      role.save
    end

    if role.default_attributes["glance"]["api"]["bind_open_address"]
      net_svc = NetworkService.new @logger
      server_nodes.each do |n|
        net_svc.allocate_ip "default", "public", "host", n
      end
    end

    # Setup virtual IPs for the clusters
    allocate_virtual_ips_for_any_cluster_in_networks_and_sync_dns(server_elements, vip_networks)

    @logger.debug("Glance apply_role_pre_chef_call: leaving")
  end
end
