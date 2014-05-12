module GlanceHelper
  class << self
    def network_settings(node)
      @ip ||= Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
      @cluster_admin_ip ||= nil

      if node[:glance][:ha][:enabled] && !@cluster_admin_ip
        cluster_vhostname = CrowbarPacemakerHelper.cluster_vhostname(node)
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
