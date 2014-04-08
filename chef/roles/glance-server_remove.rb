name "glance-server_remove"
description "Deactivate Glance Server Role services"
run_list(
  "recipe[glance::deactivate_server]"
)
default_attributes()
override_attributes()
