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

module Barclamp
  module GlanceHelper
    def api_protocols_for_glance(selected)
      options_for_select(
        [
          ["HTTP", "http"],
          ["HTTPS", "https"]
        ],
        selected.to_s
      )
    end

    def default_stores_for_glance(selected)
      options_for_select(
        [
          ["File", "file"],
          ["Swift", "swift"],
          ["Rados", "rbd"],
          ["VMware", "vsphere"]
        ],
        selected.to_s
      )
    end
  end
end
