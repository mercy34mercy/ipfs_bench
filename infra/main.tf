terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# VPC Network (optional, uses default if not created)
resource "google_compute_network" "ipfs_network" {
  count                   = var.create_vpc ? 1 : 0
  name                    = "${var.prefix}-network"
  auto_create_subnetworks = true
  description             = "Network for IPFS benchmark nodes"
}

# Firewall rules for IPFS
resource "google_compute_firewall" "ipfs_firewall" {
  name    = "${var.prefix}-allow-ipfs"
  network = var.create_vpc ? google_compute_network.ipfs_network[0].name : "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "4001", "5001", "8080"]
  }

  allow {
    protocol = "udp"
    ports    = ["4001"]
  }

  source_ranges = var.allowed_ip_ranges
  target_tags   = ["ipfs-node"]

  description = "Allow SSH and IPFS ports (4001, 5001, 8080)"
}

# Startup script to setup Docker and clone the repository
locals {
  startup_script = <<-EOT
    #!/bin/bash
    set -e

    echo "=== Starting IPFS Benchmark Node Setup ==="

    # Update package list
    apt-get update

    # Install Docker
    if ! command -v docker &> /dev/null; then
      echo "Installing Docker..."
      curl -fsSL https://get.docker.com | sh
      systemctl start docker
      systemctl enable docker
    else
      echo "Docker already installed"
    fi

    # Add user to docker group
    usermod -aG docker ${var.ssh_user}

    # Install docker-compose
    if ! command -v docker-compose &> /dev/null; then
      echo "Installing docker-compose..."
      curl -L "https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
      chmod +x /usr/local/bin/docker-compose
    else
      echo "docker-compose already installed"
    fi

    # Install git if not present
    if ! command -v git &> /dev/null; then
      apt-get install -y git
    fi

    # Install iproute2 for tc command
    apt-get install -y iproute2

    # Clone repository if specified
    %{if var.repo_url != ""}
    if [ ! -d "/home/${var.ssh_user}/ipfs_bench" ]; then
      echo "Cloning repository..."
      cd /home/${var.ssh_user}
      sudo -u ${var.ssh_user} git clone ${var.repo_url} ipfs_bench
      chown -R ${var.ssh_user}:${var.ssh_user} /home/${var.ssh_user}/ipfs_bench
    else
      echo "Repository already cloned"
    fi
    %{endif}

    # Enable IP forwarding (for tc)
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p

    echo "=== Setup completed ==="
    echo "Instance is ready for IPFS benchmarking"
    echo "SSH: gcloud compute ssh ${var.prefix}-node-$${HOSTNAME##*-} --zone=${var.zone}"
  EOT
}

# Compute Engine instances for IPFS nodes
resource "google_compute_instance" "ipfs_nodes" {
  count        = var.node_count
  name         = "${var.prefix}-node-${count.index + 1}"
  machine_type = var.machine_type
  zone         = var.zone

  tags = ["ipfs-node"]

  boot_disk {
    initialize_params {
      image = var.os_image
      size  = var.disk_size_gb
      type  = var.disk_type
    }
  }

  network_interface {
    network = var.create_vpc ? google_compute_network.ipfs_network[0].name : "default"

    access_config {
      # Ephemeral public IP
      nat_ip = var.use_static_ip ? google_compute_address.ipfs_static_ip[count.index].address : null
    }
  }

  metadata = {
    ssh-keys = var.ssh_public_key != "" ? "${var.ssh_user}:${var.ssh_public_key}" : null
  }

  metadata_startup_script = local.startup_script

  # Enable if using preemptible instances
  scheduling {
    preemptible       = var.use_preemptible
    automatic_restart = !var.use_preemptible
  }

  # Allow stopping for updates
  allow_stopping_for_update = true

  labels = {
    environment = var.environment
    purpose     = "ipfs-benchmark"
    managed_by  = "terraform"
  }
}

# Static IP addresses (optional)
resource "google_compute_address" "ipfs_static_ip" {
  count  = var.use_static_ip ? var.node_count : 0
  name   = "${var.prefix}-ip-${count.index + 1}"
  region = var.region
}
