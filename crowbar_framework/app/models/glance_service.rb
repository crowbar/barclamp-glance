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

# Turn off multi proposal support till it really works and people ask for it.
  def self.allow_multiple_proposals?
    false
  end

  def proposal_dependencies(role)
    answer = []
    answer << { "barclamp" => "database", "inst" => role.default_attributes["glance"]["database_instance"] }
    if role.default_attributes["glance"]["use_keystone"]
      answer << { "barclamp" => "keystone", "inst" => role.default_attributes["glance"]["keystone_instance"] }
    end
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
      base["deployment"]["glance"]["elements"] = {
        "glance-server" => [ nodes.first[:fqdn] ]
      }
    end

    base["attributes"][@bc_name]["git_instance"] = ""
    begin
      gitService = GitService.new(@logger)
      gits = gitService.list_active[1]
      if gits.empty?
        # No actives, look for proposals
        gits = gitService.proposals[1]
      end
      unless gits.empty?
        base["attributes"][@bc_name]["git_instance"] = gits[0]
      end
    rescue
      @logger.info("#{@bc_name} create_proposal: no git found")
    end

    base["attributes"]["glance"]["database_instance"] = ""
    begin
      databaseService = DatabaseService.new(@logger)
      dbs = databaseService.list_active[1]
      if dbs.empty?
        # No actives, look for proposals
        dbs = databaseService.proposals[1]
      end
      unless dbs.empty?
        base["attributes"]["glance"]["database_instance"] = dbs[0]
      else
        @logger.info("Glance create_proposal: no database found")
      end
    rescue
      @logger.info("Glance create_proposal: no database found")
    end

    if base["attributes"]["glance"]["database_instance"] == ""
      raise(I18n.t('model.service.dependency_missing', :name => @bc_name, :dependson => "database"))
    end

    base["attributes"]["glance"]["rabbitmq_instance"] = ""
    begin
      rabbitmqService = RabbitmqService.new(@logger)
      rabbitmqs = rabbitmqService.list_active[1]
      if rabbitmqs.empty?
        # No actives, look for proposals
        rabbitmqs = rabbitmqService.proposals[1]
      end
      base["attributes"]["glance"]["rabbitmq_instance"] = rabbitmqs[0] unless rabbitmqs.empty?
    rescue
      @logger.info("Glance create_proposal: no rabbitmq found")
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
      tnodes = role.override_attributes["glance"]["elements"]["glance-server"]
      tnodes.each do |n|
        net_svc.allocate_ip "default", "public", "host", n
      end unless tnodes.nil?
    end

    @logger.debug("Glance apply_role_pre_chef_call: leaving")
  end

end

