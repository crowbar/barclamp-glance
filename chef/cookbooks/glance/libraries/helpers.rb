module GlanceHelper
  class << self
    def keystone_settings(node)
      @keystone_settings ||= nil

      if @keystone_settings.nil?
        # we can't use get_instance from here :/
        #keystone_node = Chef::Recipe.get_instance('roles:keystone-server')
        nodes = []
        Chef::Search::Query.new.search(:node, "roles:keystone-server AND keystone_config_environment:keystone-config-#{node[:glance][:keystone_instance]}") { |o| nodes << o }
        if nodes.empty?
          keystone_node = node
        else
          keystone_node = nodes[0]
          keystone_node = node if keystone_node.name == node.name
        end

        @keystone_settings = KeystoneHelper.keystone_settings(keystone_node)
        @keystone_settings['service_user'] = node[:glance][:service_user]
        @keystone_settings['service_password'] = node[:glance][:service_password]
        Chef::Log.info("Keystone server found at #{@keystone_settings['internal_url_host']}")
      end

      @keystone_settings
    end

    def network_settings(node)
      @ip ||= Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
      @cluster_admin_ip ||= nil

      if node[:glance][:ha][:enabled] && !@cluster_admin_ip
        cluster_vhostname = PacemakerHelper.cluster_vhostname(node)
        admin_net_db = Chef::DataBagItem.load('crowbar', 'admin_network').raw_data
        @cluster_admin_ip = admin_net_db["allocated_by_name"]["#{cluster_vhostname}.#{node[:domain]}"]["address"]
      end

      @network_settings ||= {
        :ip  => @ip,

        :api => {
          :bind_host    => !node[:glance][:ha][:enabled] && node[:glance][:api][:bind_open_address] ? "0.0.0.0" : @ip,
          :bind_port    => node[:glance][:ha][:enabled] ? node[:glance][:ha][:ports][:api].to_i : node[:glance][:api][:bind_port].to_i,
          :ha_bind_host => node[:glance][:api][:bind_open_address] ? "0.0.0.0" : @cluster_admin_ip,
          :ha_bind_port => node[:glance][:api][:bind_port].to_i,
        },

        :registry => {
          :bind_host    => @ip,
          :bind_port    => node[:glance][:ha][:enabled] ? node[:glance][:ha][:ports][:registry].to_i : node[:glance][:registry][:bind_port].to_i,
          :ha_bind_host => @cluster_admin_ip,
          :ha_bind_port => node[:glance][:registry][:bind_port].to_i,
        }
      }
    end
  end
end
