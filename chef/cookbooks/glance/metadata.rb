maintainer       "Dell Crowbar Team"
maintainer_email "openstack@dell.com"
license          "Apache 2.0"
description      "Installs/Configures Glance"
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          "0.2"
depends          "keystone"
# needed for correctly apply this recipe
depends          "barclamp"
depends          "mysql"
depends          "openssl"
depends          "nagios"
