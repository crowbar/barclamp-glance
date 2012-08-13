# Copyright 2012, Dell 
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

  def proposal_dependencies(prop_config)
    answer = []
    hash = prop_config.config_hash
    if hash["database"] == "mysql"
      answer << { "barclamp" => "mysql", "inst" => hash["mysql_instance"] }
    end
    if hash["use_keystone"]
      answer << { "barclamp" => "keystone", "inst" => hash["keystone_instance"] }
    end
    answer
  end

  def create_proposal
    @logger.debug("Glance create_proposal: entering")
    base = super

    nodes = Node.all
    nodes.delete_if { |n| n.nil? or n.is_admin? }
    if nodes.size >= 1
      add_role_to_instance_and_node(n[0].name, base.name, "glance-server")
    end

    hash = base.config_hash
    hash["mysql_instance"] = ""
    begin
      mysql = Barclamp.find_by_name("mysql")
      mysqls = mysql.active_proposals
      if mysqls.empty?
        # No actives, look for proposals
        mysqls = mysql.proposals
      end
      unless mysqls.empty?
        hash["mysql_instance"] = mysqls[0].name
      end
      hash["database"] = "mysql"
    rescue
      hash["database"] = "mysql"
      @logger.info("Glance create_proposal: no mysql found")
    end
    
    hash["keystone_instance"] = ""
    begin
      keystone = Barclamp.find_by_name("keystone")
      keystones = keystone.active_proposals
      if keystones.empty?
        # No actives, look for proposals
        keystones = keystone.proposals
      end
      if keystones.empty?
        hash["use_keystone"] = false
      else
        hash["keystone_instance"] = keystones[0].name
        hash["use_keystone"] = true
      end
    rescue
      @logger.info("Glance create_proposal: no keystone found")
      hash["use_keystone"] = false
    end
    hash["service_password"] = '%012d' % rand(1e12)
    hash["api"]["bind_open_address"] = true
    hash["registry"]["bind_open_address"] = true

    base.config_hash = hash

    @logger.debug("Glance create_proposal: exiting")
    base
  end

  def apply_role_pre_chef_call(old_config, new_config, all_nodes)
    @logger.debug("Glance apply_role_pre_chef_call: entering #{all_nodes.inspect}")
    return if all_nodes.empty?

    # Update images paths
    pc = Barclamp.find_by_name("provisioner").get_proposal("default").active_config
    nodes = pc.get_nodes_by_role("provisioner-server")
    unless nodes.nil? or nodes.length < 1
      admin_ip = nodes[0].address.addr
      web_port = pc.config_hash["web_port"]

      # substitute the admin web portal
      dep_config = new_config.config_hash
      new_array = []
      dep_config["images"].each do |item|
        new_array << item.gsub("|ADMINWEB|", "#{admin_ip}:#{web_port}")
      end
      dep_config["images"] = new_array
      new_config.config_hash = dep_config
    end

    # Make sure the bind hosts are in the admin network
    all_nodes.each do |node|
      admin_address = node.address.addr

      chash = new_config.get_node_config_hash(node)
      chash[:glance] = {} if node.crowbar[:glance].nil?
      chash[:glance][:api_bind_host] = admin_address
      chash[:glance][:registry_bind_host] = admin_address
      new_config.set_node_config_hash(node, chash)
    end
    @logger.debug("Glance apply_role_pre_chef_call: leaving")
  end

end

