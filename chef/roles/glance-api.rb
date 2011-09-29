name "glance-api"
description "Glance API Role - Image Registry and Delivery Service for the cloud"
run_list(
         "recipe[glance::api]",
         "recipe[glance::cache]",
         "recipe[glance::monitor]"
)
default_attributes()
override_attributes()
