#
# Inception Bastion instance
#

resource "google_compute_instance" "bastion" {
  name         = element(split(".", var.vpc_dns_zone), 0)
  machine_type = var.bastion_instance_type
  zone         = data.google_compute_zones.available.names[0]

  can_ip_forward            = true
  allow_stopping_for_update = true

  tags = [
    "bastion-ssh",
    "bastion-vpn",
    "bastion-smtp-ext",
    "bastion-smtp-int",
    "bastion-proxy",
    "bastion-deny-dmz",
  ]

  boot_disk {
    initialize_params {
      image = var.bastion_use_project_image ? data.google_compute_image.bastion[0].self_link : google_compute_image.bastion[0].self_link
      size  = var.bastion_root_disk_size
    }
  }

  attached_disk {
    source = google_compute_disk.bastion-data.self_link
  }

  network_interface {
    subnetwork = google_compute_subnetwork.dmz.self_link
    network_ip = google_compute_address.bastion-dmz.address

    access_config {
      nat_ip = google_compute_address.bastion-public.address

      # public_ptr_domain_name = google_dns_record_set.vpc-public.name
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.admin.self_link
    network_ip = google_compute_address.bastion-admin.address
  }

  metadata = {
    user-data          = module.config.bastion_cloud_init_config
    user-data-encoding = "base64"
  }

  lifecycle {
    ignore_changes = [metadata]
  }
}

#
# Attached disk for saving persistant data. This disk needs to be
# large enough for any installation packages concourse downloads.
#

resource "google_compute_disk" "bastion-data" {
  name = "${var.vpc_name}-bastion-data"
  type = "pd-standard"
  zone = data.google_compute_zones.available.names[0]
  size = var.bastion_data_disk_size
}

#
# Image
#

locals {
  gs_image_region = element(split("-", var.region), 0)
  gs_image_buckets = {
    "us": "ab-bastion-images-us",
    "northamerica": "ab-bastion-images-asia",
    "southamerica": "ab-bastion-images-asia",
    "europe": "ab-bastion-images-eu",
    "asia": "ab-bastion-images-asia",
    "australia": "ab-bastion-images-asia",
  }
  bastion_image_url = "https://storage.cloud.google.com/${local.gs_image_buckets[local.gs_image_region]}/${var.bastion_image_name}.tar.gz?authuser=1"
}

# Lookup image in current project's image repository
data "google_compute_image" "bastion" {
  count = var.bastion_use_project_image ? 1 : 0

  name = var.bastion_image_name
}

# Create image using the given url
resource "google_compute_image" "bastion" {
  count = var.bastion_use_project_image ? 0 : 1
  name = "${var.vpc_name}-bastion-img${random_string.bastion-image-key.result}"

  raw_disk {
    source = local.bastion_image_url
  }
}

resource "random_string" "bastion-image-key" {
  length = 7
  upper = false
  special = false
}

#
# Networking
#

resource "google_compute_address" "bastion-dmz" {
  name         = "${var.vpc_name}-bastion-dmz"
  address_type = "INTERNAL"

  subnetwork = google_compute_subnetwork.dmz.self_link
  region     = var.region

  address = cidrhost(google_compute_subnetwork.dmz.ip_cidr_range, -3)
}

resource "google_compute_address" "bastion-admin" {
  name         = "${var.vpc_name}-bastion-admin"
  address_type = "INTERNAL"

  subnetwork = google_compute_subnetwork.admin.self_link
  region     = var.region

  address = cidrhost(google_compute_subnetwork.admin.ip_cidr_range, -3)
}

resource "google_compute_address" "bastion-public" {
  name         = "${var.vpc_name}-bastion"
  address_type = "EXTERNAL"

  region = var.region
}

#
# Security (Firewall rules for the inception bastion instance)
#

resource "google_compute_firewall" "bastion-ssh" {
  count = var.bastion_allow_public_ssh ? 1 : 0 

  name    = "${var.vpc_name}-bastion-ssh"
  network = google_compute_network.dmz.self_link

  allow {
    protocol = "tcp"
    ports    = [var.bastion_admin_ssh_port]
  }

  priority      = "500"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["bastion-ssh"]
}

resource "google_compute_firewall" "bastion-vpn" {
  count = length(var.vpn_type) == 0 ? 0 : 1 

  name    = "${var.vpc_name}-bastion-vpn"
  network = google_compute_network.dmz.self_link

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  # OpenVPN
  dynamic "allow" {
    for_each = var.vpn_type == "openvpn" && length(var.ovpn_server_port) > 0 ? [1] : []
    content {
      protocol = var.ovpn_protocol
      ports    = [var.ovpn_server_port]
    }
  }
  # IPSec/IKEv2
  dynamic "allow" {
    for_each = var.vpn_type == "ipsec" ? [1] : []
    content {
      protocol = "udp"
      ports    = ["500", "4500"]
    }
  }
  # VPN Tunnel
  dynamic "allow" {
    for_each = length(var.tunnel_vpn_port_start) > 0 && length(var.tunnel_vpn_port_end) > 0 ? [1] : []
    content {
      protocol = "udp"
      ports    = ["${var.tunnel_vpn_port_start}-${var.tunnel_vpn_port_end}"]
    }
  }
  dynamic "allow" {
    for_each = length(var.tunnel_vpn_port_start) > 0 && length(var.tunnel_vpn_port_end) > 0 ? [1] : []
    content {
      protocol = "tcp"
      ports    = ["${var.tunnel_vpn_port_start}-${var.tunnel_vpn_port_end}"]
    }
  }
  # Allow ICMP
  dynamic "allow" {
    for_each = var.allow_bastion_icmp ? [1] : []
    content {
      protocol = "icmp"
    }
  }

  priority      = "500"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["bastion-vpn"]
}

resource "google_compute_firewall" "bastion-smtp-ext" {
  count = length(var.smtp_relay_host) == 0 ? 0 : 1 

  name    = "${var.vpc_name}-bastion-smtp-ext"
  network = google_compute_network.dmz.self_link

  allow {
    protocol = "tcp"
    ports    = ["25"]
  }

  priority      = "500"
  direction     = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["bastion-smtp-ext"]
}

resource "google_compute_firewall" "bastion-smtp-int" {
  count = length(var.smtp_relay_host) == 0 ? 0 : 1 

  name    = "${var.vpc_name}-bastion-smtp-int"
  network = google_compute_network.admin.self_link

  allow {
    protocol = "tcp"
    ports    = ["2525"]
  }

  priority      = "500"
  direction     = "INGRESS"
  source_ranges = [var.vpn_network, var.vpc_cidr]
  target_tags   = ["bastion-smtp-int"]
}

resource "google_compute_firewall" "bastion-proxy" {
  count = length(var.squidproxy_server_port) == 0 ? 0 : 1 

  name    = "${var.vpc_name}-bastion-proxy"
  network = google_compute_network.admin.self_link

  allow {
    protocol = "tcp"
    ports    = [var.squidproxy_server_port]
  }

  priority      = "500"
  direction     = "INGRESS"
  source_ranges = [var.vpn_network, var.vpc_cidr]
  target_tags   = ["bastion-proxy"]
}

resource "google_compute_firewall" "bastion-deny-vpc" {
  name    = "${var.vpc_name}-bastion-deny-vpc"
  network = google_compute_network.admin.self_link

  deny {
    protocol = "all"
  }

  priority      = "599"
  direction     = "INGRESS"
  source_ranges = [var.vpc_cidr]
  target_tags   = ["bastion-deny-vpc"]
}

resource "google_compute_firewall" "bastion-deny-dmz" {
  name    = "${var.vpc_name}-bastion-deny-dmz"
  network = google_compute_network.dmz.self_link

  deny {
    protocol = "all"
  }

  priority      = "599"
  direction     = "INGRESS"
  source_ranges = [google_compute_subnetwork.dmz.ip_cidr_range]
  target_tags   = ["bastion-deny-dmz"]
}

#
# Bastion instance will also provide NAT for VPC
#

resource "google_compute_route" "nat-route-admin" {
  name = "${var.vpc_name}-nat-route-admin"

  dest_range             = "0.0.0.0/0"
  network                = google_compute_network.admin.name
  next_hop_instance      = google_compute_instance.bastion.name
  next_hop_instance_zone = google_compute_instance.bastion.zone
  priority               = 800

  tags = ["nat-${var.vpc_name}-${var.region}"]
}
