# Copyright 2011, Dell 
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#  http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License. 
# 

class GlanceService < ServiceObject

  def initialize(thelogger)
    @bc_name = "glance"
    @logger = thelogger
  end

  def self.allow_multiple_proposals?
    true
  end

  def proposal_dependencies(role)
    answer = []
    if role.default_attributes["glance"]["database"] == "mysql"
      answer << { "barclamp" => "mysql", "inst" => role.default_attributes["glance"]["mysql_instance"] }
    end
    if role.default_attributes["glance"]["use_keystone"]
      answer << { "barclamp" => "keystone", "inst" => role.default_attributes["glance"]["keystone_instance"] }
    end
    answer
  end

  def create_proposal
    @logger.debug("Glance create_proposal: entering")
    base = super

    nodes = NodeObject.all
    nodes.delete_if { |n| n.nil? or n.admin? }
    if nodes.size >= 1
      base["deployment"]["glance"]["elements"] = {
        "glance-server" => [ nodes.first[:fqdn] ]
      }
    end

    base["attributes"]["glance"]["mysql_instance"] = ""
    begin
      mysqlService = MysqlService.new(@logger)
      mysqls = mysqlService.list_active[1]
      if mysqls.empty?
        # No actives, look for proposals
        mysqls = mysqlService.proposals[1]
      end
      if mysqls.empty?
        base["attributes"]["glance"]["database"] = "sqlite"
      else
        base["attributes"]["glance"]["mysql_instance"] = mysqls[0]
        base["attributes"]["glance"]["database"] = "mysql"
      end
    rescue
      base["attributes"]["glance"]["database"] = "sqlite"
      @logger.info("Glance create_proposal: no mysql found")
    end
    
    base["attributes"]["glance"]["keystone_instance"] = ""
    begin
      keystoneService = KeystoneService.new(@logger)
      keystones = keystoneService.list_active[1]
      if keystones.empty?
        # No actives, look for proposals
        keystones = keystoneService.proposals[1]
      end
      if keystones.empty?
        base["attributes"]["glance"]["use_keystone"] = false
      else
        base["attributes"]["glance"]["keystone_instance"] = keystones[0]
        base["attributes"]["glance"]["use_keystone"] = true
      end
    rescue
      @logger.info("Glance create_proposal: no keystone found")
      base["attributes"]["glance"]["use_keystone"] = false
    end
    base["attributes"]["glance"]["service_password"] = '%012d' % rand(1e12)

    @logger.debug("Glance create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_role, role, all_nodes)
    @logger.debug("Glance apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    # Update images paths
    nodes = NodeObject.find("roles:provisioner-server")
    unless nodes.nil? or nodes.length < 1
      admin_ip = nodes[0].address.addr
      web_port = nodes[0]["provisioner"]["web_port"]
      # substitute the admin web portal
      new_array = []
      role.default_attributes["glance"]["images"].each do |item|
        new_array << item.gsub("|ADMINWEB|", "#{admin_ip}:#{web_port}")
      end
      role.default_attributes["glance"]["images"] = new_array
      role.save
    end

    # Make sure the bind hosts are in the admin network
    all_nodes.each do |n|
      node = NodeObject.find_node_by_name n

      admin_address = node.address.addr
      node.crowbar[:glance] = {} if node.crowbar[:glance].nil?
      node.crowbar[:glance][:api_bind_host] = admin_address
      node.crowbar[:glance][:registry_bind_host] = admin_address

      node.save
    end
    @logger.debug("Glance apply_role_pre_chef_call: leaving")
  end

end

