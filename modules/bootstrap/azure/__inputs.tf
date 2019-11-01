#
# Google compute region
#
variable "region" {
  type = string
}

#
# Certificate Subject data for certificate creation
#
variable "company_name" {
  type = string
}

variable "organization_name" {
  type = string
}

variable "locality" {
  type = string
}

variable "province" {
  type = string
}

variable "country" {
  type = string
}

#
# Root CA key and cert to use for signing self signed certificates
#
variable "root_ca_key" {
  default = ""
}

variable "root_ca_cert" {
  default = ""
}

#
# Resource group containing resources 
# required to build the VPC
#
variable "source_resource_group" {
  default = "default"
}

#
# VPC and network variables
#
variable "vpc_name" {
  type = string
}

# VPC DNS zone
variable "vpc_dns_zone" {
  type = string
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "vpc_subnet_bits" {
  default = 8
}

variable "vpc_subnet_start" {
  default = 10
}

variable "vpc_internal_dns_zones" {
  default = [""]
}

variable "vpc_internal_dns_records" {
  default = []
}

variable "dmz_cidr" {
  default = ""
}

variable "admin_cidr" {
  default = ""
}

variable "max_azs" {
  default = 1
}

# Internal CIDR for all VPC address 
# spaces across all regions
variable "global_internal_cidr" {
  default = ""
}

#
# Local file path to write SSH private key for bastion instance
#
variable "ssh_key_file_path" {
  default = ""
}

#
# Bastion inception instance variables
#
variable "bastion_instance_type" {
  default = "Standard_DS2_v2"
}

variable "bastion_image_name" {
  default = "appbricks-inceptor-bastion"
}

variable "bastion_root_disk_size" {
  default = 50
}

variable "bastion_data_disk_size" {
  default = 250
}

variable "bastion_host_name" {
  default = ""
}

variable "bastion_use_fqdn" {
  default = true
}

# Note: this has no effect on azure
# as you cannot create an explicit
# rule for ICMP.
variable "allow_bastion_icmp" {
  default = false
}

#
# Certify bastion host using letsencrypt certificates
#
variable "certify_bastion" {
  default = false
}

#
# DNS resolvers for the  server
#
variable "bastion_dns" {
  # see: https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
  default = "168.63.129.16"
}

#
# Bastion access configuration
#
variable "bastion_admin_ssh_port" {
  default = "22"
}

variable "bastion_admin_user" {
  default = "bastion-admin"
}

variable "bastion_allow_public_ssh" {
  default = true
}

#
# VPN configuration
#
variable "vpn_type" {
  # one of "openvpn" or "ipsec"
  default = ""
}

variable "vpn_network" {
  default = "192.168.111.0/24"
}

variable "vpn_tunnel_all_traffic" {
  default = "no"
}

variable "vpn_idle_action" {
  default = "none"
}

variable "vpn_users" {
  default = []
}

#
# OpenVPN configuration
#
variable "ovpn_server_port" {
  default = ""
}

variable "ovpn_protocol" {
  default = "udp"
}

#
# Enable tunnelling of VPN within another tunnel 
# when firewalls and telco's block OpenVPN via
# deep-packet-inspection.
#
variable "tunnel_vpn_port_start" {
  default = ""
}

variable "tunnel_vpn_port_end" {
  default = ""
}

#
# Wireguard configuration
#
variable "wireguard_port" {
  default = ""
}

variable "wireguard_subnet_ip" {
  default = "192.168.112.1/24"
}

#
# Concourse
#
variable "concourse_server_port" {
  default = ""
}

variable "concourse_admin_password" {
  default = "Passw0rd"
}

# Concourse bootstrap pipeline
variable "bootstrap_pipeline_file" {
  default = ""
}

variable "bootstrap_pipeline_vars" {
  default = ""
}

# Path to cloud inceptor repository provided as input 
# to concourse tasks. This is required to be able to 
# locate tasks such as notifications found in that
# repository. This path should be from the build 
# root of the concourse build container and the
# first element would typically be the name of
# the concourse automation repository resource path.
variable "pipeline_automation_path" {
  default = "automation"
}

# Email to send concourse job notifications to
variable "notification_email" {
  default = ""
}

#
# Configure SMTP
#
variable "smtp_relay_host" {
  default = ""
}

variable "smtp_relay_port" {
  default = ""
}

variable "smtp_relay_api_key" {
  default = ""
}

#
# Squid Proxy port
#
variable "squidproxy_server_port" {
  default = ""
}

#
# Jumpbox
#
variable "deploy_jumpbox" {
  default = true
}

variable "jumpbox_data_disk_size" {
  default = "160"
}