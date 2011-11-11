name "glance-server"
description "Glance Server Role - Image Registry and Delivery Service for the cloud"
run_list(
         "recipe[glance::api]",
         "recipe[glance::registry]",
         "recipe[glance::cache]",
         "recipe[glance::scrubber]",
         "recipe[glance::setup]",
         "recipe[glance::monitor]"
)
default_attributes()
override_attributes()
