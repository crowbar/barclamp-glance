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

unless platform == "suse"
  override[:glance][:user]="glance"
  override[:glance][:group]="glance"
else
  override[:glance][:user]="openstack-glance"
  override[:glance][:group]="openstack-glance"
end

default[:glance][:verbose] = "False"
default[:glance][:debug] = "False"

default[:glance][:api][:protocol] = "http"
default[:glance][:api][:bind_host] = ipaddress
default[:glance][:api][:bind_port] = "9292"
default[:glance][:api][:log_file] = "/var/log/glance/api.log"
default[:glance][:api][:config_file]="/etc/glance/glance-api.conf"

default[:glance][:registry][:bind_host] = ipaddress
default[:glance][:registry][:bind_port] = "9191"
default[:glance][:registry][:log_file] = "/var/log/glance/registry.log"
default[:glance][:registry][:config_file]="/etc/glance/glance-registry.conf"

default[:glance][:cache][:log_file] = "/var/log/glance/cache.log"
default[:glance][:cache][:config_file]="/etc/glance/glance-cache.conf"

default[:glance][:scrubber][:log_file] = "/var/log/glance/scrubber.log"
default[:glance][:scrubber][:config_file]="/etc/glance/glance-scrubber.conf"

default[:glance][:working_directory]="/var/lib/glance"
default[:glance][:image_cache_datadir] = "/var/lib/glance/image-cache/"

default[:glance][:sql_idle_timeout] = "3600"

#default_store choices are: file, http, https, swift, s3
default[:glance][:default_store] = "file"
default[:glance][:filesystem_store_datadir] = "/var/lib/glance/images"

default[:glance][:swift][:store_container] = "glance"
default[:glance][:swift][:store_create_container_on_put] = true

# automatically glance upload the tty linux image. (glance::setup recipe)
default[:glance][:tty_linux_image] = "http://c3226372.r72.cf0.rackcdn.com/tty_linux.tar.gz"

# declare what needs to be monitored
node.set[:glance][:monitor]={}
node.set[:glance][:monitor][:svcs] = []
node.set[:glance][:monitor][:ports]={}

default[:glance][:ssl][:certfile] = "/etc/glance/ssl/certs/signing_cert.pem"
default[:glance][:ssl][:keyfile] = "/etc/glance/ssl/private/signing_key.pem"
default[:glance][:ssl][:generate_certs] = false
default[:glance][:ssl][:insecure] = false
default[:glance][:ssl][:cert_required] = false
default[:glance][:ssl][:ca_certs] = "/etc/glance/ssl/certs/ca.pem"
