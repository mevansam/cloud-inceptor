#
# SSH Key
#

resource "tls_private_key" "bastion-ssh-key" {
  algorithm = "RSA"
  rsa_bits  = "4096"
}

resource "local_file" "bastion-ssh-key" {
  content  = "${tls_private_key.bastion-ssh-key.private_key_pem}"
  filename = "${var.ssh_key_file_path}/bastion-admin-ssh-key.pem"

  provisioner "local-exec" {
    command = "chmod 0600 ${var.ssh_key_file_path}/bastion-admin-ssh-key.pem"
  }
}

#
# Bastion configuration templates
#

locals {
  bastion_internal_ip = "${length(var.bastion_admin_itf_ip) > 0 
    ? var.bastion_admin_itf_ip 
    : var.bastion_dmz_itf_ip}"

  admin_email = "${var.bastion_admin_user}@${var.vpc_dns_zone}"

  # Create shorter email key if it is too long when 
  # vpc dns is included, as vpn cert creation limits 
  # length of string accepted.
  vpn_email_key = "${length(local.admin_email) > 40 
    ? join("@", list(var.bastion_admin_user, var.vpc_name))
    : local.admin_email}"
}

data "template_cloudinit_config" "bastion-cloudinit" {
  gzip          = true
  base64_encode = true

  part {
    content = <<USER_DATA
#cloud-config

write_files:
# Persistant and Data Volumes
- encoding: b64
  content: ${base64encode(data.template_file.mount-data-volume.rendered)}
  path: /root/mount-data-volume.sh
  permissions: '0744'

# Service configuration
- encoding: b64
  content: ${base64encode(data.template_file.bastion-config.rendered)}
  path: /root/bastion-config.yml
  permissions: '0744'

# Web Server SSL certificates
- encoding: b64
  content: ${base64encode(tls_self_signed_cert.root-ca.cert_pem)}
  path: /etc/ssl/certs/bastion_web_ca.pem
  permissions: '0644'
- encoding: b64
  content: ${base64encode(tls_locally_signed_cert.bastion-web.cert_pem)}
  path: /etc/ssl/certs/bastion_web_cert.pem
  permissions: '0644'
- encoding: b64
  content: ${base64encode(tls_private_key.bastion-web.private_key_pem)}
  path: /etc/ssl/private/bastion_web_key.pem
  permissions: '0644'

# Web Server home page
- encoding: b64
  content: ${base64encode(data.template_file.www-static-index.rendered)}
  path: /var/www/html/index.html
  permissions: '0644'

# Bootstrap Pipeline
- encoding: b64
  content: ${base64encode(file(length(var.bootstrap_pipeline_file) == 0 ? "${path.module}/_placeholder_" : var.bootstrap_pipeline_file))}
  path: /root/bootstrap.yml
  permissions: '0644'
- encoding: b64
  content: ${base64encode(data.template_file.bootstrap-pipeline-vars.rendered)}
  path: /root/bootstrap-vars.yml
  permissions: '0644'

network:
  config: disabled

runcmd: 
- /root/mount-data-volume.sh 2>&1 | tee -a /var/log/mount-data-volume.log
- mv /root/bastion-config.yml /root/config.yml
- /root/.bin/configure_network 2>&1 | tee -a /var/log/configure_network.log
- /root/.bin/configure_powerdns 2>&1 | tee -a /var/log/configure_powerdns.log
- /root/.bin/configure_smtp 2>&1 | tee -a /var/log/configure_smtp.log
- /root/.bin/configure_openvpn 2>&1 | tee -a /var/log/configure_openvpn.log
- /root/.bin/configure_squidproxy 2>&1 | tee -a /var/log/configure_squidproxy.log
- /root/.bin/configure_concourse 2>&1 | tee -a /var/log/configure_concourse.log
- chmod 0600 /var/log/configure_*.log
- chmod 0600 /var/log/cloud-init*.log

USER_DATA
  }
}

data "template_file" "mount-data-volume" {
  template = "${file("${path.module}/scripts/mount-volume.sh")}"

  vars {
    attached_device_name = "${var.data_volume_name}"
    mount_directory      = "/data"
    world_readable       = "false"
  }
}

data "template_file" "bastion-config" {
  template = <<CONFIG
---
server:
  host: ${var.bastion_public_ip}
  fqdn: ${var.bastion_fqdn}
  use_fqdn: ${var.bastion_use_fqdn}
  dmz_itf_ip: ${var.bastion_dmz_itf_ip}
  lan_interfaces: '${join(",", var.bastion_nic_config)}'
  dns_resolvers: ${length(var.bastion_dns) == 0 ? local.bastion_internal_ip: var.bastion_dns}
  enable_dhcpd: ${var.enable_bastion_as_dhcpd}
  admin_ssh_port: ${var.bastion_admin_ssh_port}
  admin_user: ${var.bastion_admin_user}
  admin_passwd: ${random_string.bastion-admin-password.result}
  admin_ssh_public_key: ${tls_private_key.bastion-ssh-key.public_key_openssh}
  docker_mount_path: /data

powerdns:
  dns_zones: ${join(" ", var.vpc_internal_dns_zones)}
  dns_records: ${join(" ", var.vpc_internal_dns_records)}
  allowed_subnets: ${var.vpc_cidr},${var.vpn_network}
  ns_ip: ${local.bastion_internal_ip}
  api_key: ${random_string.powerdns-api-key.result}

smtp:
  relay_host: ${var.smtp_relay_host}
  relay_port: ${var.smtp_relay_port}
  relay_api_key: ${var.smtp_relay_api_key}
  internal_smtp_host: ${local.bastion_internal_ip}
  internal_smtp_port: 2525
  networks: 172.16.0.0/12 ${var.vpc_cidr} ${var.bastion_public_ip}

openvpn:
  port: ${var.vpn_server_port}
  protocol: ${var.vpn_protocol}
  subnet: ${var.vpn_network}
  netmask: ${cidrnetmask(var.vpn_network)}
  server_domain: ${var.vpc_dns_zone}
  server_description: ${var.vpc_name}-vpn
  tunnel_all_traffic: ${var.vpn_tunnel_all_traffic}
  vpn_cert:
    name: ${var.vpc_name}_VPN
    org: ${var.organization_name}
    email: ${local.vpn_email_key}
    city: ${var.locality}
    province: ${var.province}
    country: ${var.country}
    ou: ${var.vpc_name}
    cn: ${var.vpc_dns_zone}
  users: '${var.vpn_users}'

concourse:
  port: ${length(var.concourse_server_port) == 0 ? "" : "${var.concourse_server_port}"}
  password: ${var.concourse_admin_password}
  vpc_name: ${var.vpc_name}
  pipeline_automation_path: '${var.pipeline_automation_path}'
  notification_email: '${var.notification_email}'
CONFIG
}

data "template_file" "www-static-index" {
  template = "${file("${path.module}/www-static-home/index.html")}"

  vars {
    environment = "${var.vpc_name}"
  }
}

data "template_file" "bootstrap-pipeline-vars" {
  template = "${var.bootstrap_pipeline_vars}"
}

resource "random_string" "bastion-admin-password" {
  length  = 32
  special = false
}

resource "random_string" "powerdns-api-key" {
  length  = 32
  special = false
}
