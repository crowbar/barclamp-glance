#
# Cookbook Name:: glance
# Attributes:: default
#
# Copyright 2011, Opscode, Inc.
# Copyright 2011, Dell, Inc.
# Copyright 2013, SUSE Linux Products GmbH
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

override[:glance][:user]="glance"
override[:glance][:group]="glance"

default[:glance][:verbose] = "False"
default[:glance][:debug] = "False"

default[:glance][:config_dir] = "/etc/glance"

default[:glance][:max_header_line] = 16384

default[:glance][:db][:password] = "" # set by wrapper
default[:glance][:db][:user] = "glance"
default[:glance][:db][:database] = "glance"

default[:glance][:api][:protocol] = "http"
default[:glance][:api][:bind_port] = "9292"
default[:glance][:api][:log_file] = "/var/log/glance/api.log"
default[:glance][:api][:config_file]="/etc/glance/glance-api.conf"
default[:glance][:api][:service_name] = "glance-api"

default[:glance][:registry][:bind_port] = "9191"
default[:glance][:registry][:log_file] = "/var/log/glance/registry.log"
default[:glance][:registry][:config_file]="/etc/glance/glance-registry.conf"
default[:glance][:registry][:service_name] = "glance-registry"

default[:glance][:cache][:log_file] = "/var/log/glance/cache.log"
default[:glance][:cache][:config_file]="/etc/glance/glance-cache.conf"

default[:glance][:scrubber][:log_file] = "/var/log/glance/scrubber.log"
default[:glance][:scrubber][:config_file]="/etc/glance/glance-scrubber.conf"

default[:glance][:working_directory]="/var/lib/glance"
default[:glance][:image_cache_datadir] = "/var/lib/glance/image-cache/"

default[:glance][:sql_idle_timeout] = "3600"

default[:glance][:glance_stores] = ["glance.store.filesystem.Store",
                                    "glance.store.http.Store",
                                    "glance.store.cinder.Store",
                                    "glance.store.rbd.Store",
                                    "glance.store.swift.Store"]

#default_store choices are: file, http, https, rbd, swift, s3
default[:glance][:default_store] = "file"
default[:glance][:filesystem_store_datadir] = "/var/lib/glance/images"

default[:glance][:swift][:store_container] = "glance"
default[:glance][:swift][:store_create_container_on_put] = true

# automatically glance upload the tty linux image. (glance::setup recipe)
default[:glance][:tty_linux_image] = "http://c3226372.r72.cf0.rackcdn.com/tty_linux.tar.gz"

# declare what needs to be monitored
node[:glance][:monitor]={}
node[:glance][:monitor][:svcs] = []
node[:glance][:monitor][:ports]={}

default[:glance][:ssl][:certfile] = "/etc/glance/ssl/certs/signing_cert.pem"
default[:glance][:ssl][:keyfile] = "/etc/glance/ssl/private/signing_key.pem"
default[:glance][:ssl][:generate_certs] = false
default[:glance][:ssl][:insecure] = false
default[:glance][:ssl][:cert_required] = false
default[:glance][:ssl][:ca_certs] = "/etc/glance/ssl/certs/ca.pem"

if %w(redhat centos suse).include?(node[:platform])
  default[:glance][:api][:service_name] = "openstack-glance-api"
  default[:glance][:registry][:service_name] = "openstack-glance-registry"
end

# HA
default[:glance][:ha][:enabled] = false
# When HAproxy listens on the API port, make service listen elsewhere
default[:glance][:ha][:ports][:api]      = 5510
default[:glance][:ha][:ports][:registry] = 5511
# pacemaker definitions
default[:glance][:ha][:api][:op][:monitor][:interval] = "10s"
default[:glance][:ha][:api][:agent]     = "lsb:#{default[:glance][:api][:service_name]}"
default[:glance][:ha][:registry][:op][:monitor][:interval] = "10s"
default[:glance][:ha][:registry][:agent]= "lsb:#{default[:glance][:registry][:service_name]}"
