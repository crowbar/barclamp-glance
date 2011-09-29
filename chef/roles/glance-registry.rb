name "glance-registry"
description "Glance Registry Role - Image Registry and Delivery Service for the cloud"
run_list(
         "recipe[glance::registry]",
         "recipe[glance::monitor]"
)
default_attributes()
override_attributes()
