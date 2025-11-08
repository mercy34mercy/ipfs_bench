variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "regions" {
  description = "Map of region configurations for IPFS nodes"
  type = map(object({
    region = string
    zone   = string
  }))
  default = {
    tokyo = {
      region = "asia-northeast1"
      zone   = "asia-northeast1-a"
    }
    osaka = {
      region = "asia-northeast2"
      zone   = "asia-northeast2-a"
    }
    singapore = {
      region = "asia-southeast1"
      zone   = "asia-southeast1-a"
    }
    taiwan = {
      region = "asia-east1"
      zone   = "asia-east1-a"
    }
    uswest = {
      region = "us-west1"
      zone   = "us-west1-a"
    }
    europe = {
      region = "europe-west1"
      zone   = "europe-west1-b"
    }
  }
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "ipfs-bench"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "machine_type" {
  description = "GCP machine type for instances"
  type        = string
  default     = "n1-standard-2"
  # n1-standard-2: 2 vCPUs, 7.5 GB memory
  # n2-standard-2: 2 vCPUs, 8 GB memory (newer generation)
  # e2-standard-2: 2 vCPUs, 8 GB memory (cost-optimized)
}

variable "os_image" {
  description = "OS image for instances"
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
  # Other options:
  # - "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
  # - "debian-cloud/debian-11"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 30
}

variable "disk_type" {
  description = "Boot disk type (pd-standard, pd-ssd, pd-balanced)"
  type        = string
  default     = "pd-standard"
  # pd-standard: Standard persistent disk (cheapest)
  # pd-balanced: Balanced persistent disk (good performance/cost)
  # pd-ssd: SSD persistent disk (fastest, most expensive)
}

variable "use_preemptible" {
  description = "Use preemptible VMs (cheaper but can be terminated)"
  type        = bool
  default     = false
}

variable "use_static_ip" {
  description = "Allocate static external IP addresses"
  type        = bool
  default     = false
}

variable "create_vpc" {
  description = "Create a new VPC network (false = use default VPC)"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of CIDR ranges allowed to access the instances"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  # For better security, restrict to your IP:
  # default = ["YOUR_IP_ADDRESS/32"]
}

variable "ssh_user" {
  description = "SSH user name"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "SSH public key for instance access (optional, leave empty to use gcloud ssh)"
  type        = string
  default     = ""
  # Example: "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@example.com"
}

variable "repo_url" {
  description = "Git repository URL to clone on startup (optional)"
  type        = string
  default     = ""
  # Example: "https://github.com/your-username/ipfs_bench.git"
}
