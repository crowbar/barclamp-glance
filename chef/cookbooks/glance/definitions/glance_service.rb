define :glance_service do

  glance_name="glance-#{params[:name]}"
  glance_name="openstack-glance-#{params[:name]}" if %w(redhat centos suse).include?(node.platform)
  short_name="#{params[:name]}"

  service glance_name do
    if (platform?("ubuntu") && node.platform_version.to_f >= 10.04)
      restart_command "stop #{glance_name} ; start #{glance_name}"
      stop_command "stop #{glance_name}"
      start_command "start #{glance_name}"
      status_command "status #{glance_name} | cut -d' ' -f2 | cut -d'/' -f1 | grep start"
    end
    supports :status => true, :restart => true
    action [:enable, :start]
    subscribes :restart, resources(:template => node[:glance][short_name][:config_file]), :immediately
    subscribes :restart, resources(:template => node[:glance][short_name][:paste_ini]), :immediately
  end

end
