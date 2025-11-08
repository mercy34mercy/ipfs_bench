output "instance_names" {
  description = "Names of the created IPFS node instances"
  value       = { for k, v in google_compute_instance.ipfs_nodes : k => v.name }
}

output "instance_ids" {
  description = "IDs of the created instances"
  value       = { for k, v in google_compute_instance.ipfs_nodes : k => v.instance_id }
}

output "instance_zones" {
  description = "Zones where instances are deployed"
  value       = { for k, v in google_compute_instance.ipfs_nodes : k => v.zone }
}

output "external_ips" {
  description = "External IP addresses of the instances"
  value       = { for k, v in google_compute_instance.ipfs_nodes : k => v.network_interface[0].access_config[0].nat_ip }
}

output "internal_ips" {
  description = "Internal IP addresses of the instances"
  value       = { for k, v in google_compute_instance.ipfs_nodes : k => v.network_interface[0].network_ip }
}

output "ssh_commands" {
  description = "SSH commands to connect to each instance"
  value = {
    for k, instance in google_compute_instance.ipfs_nodes :
    k => "gcloud compute ssh ${instance.name} --zone=${instance.zone} --project=${var.project_id}"
  }
}

output "ssh_commands_with_user" {
  description = "SSH commands with custom user"
  value = {
    for k, instance in google_compute_instance.ipfs_nodes :
    k => "ssh ${var.ssh_user}@${instance.network_interface[0].access_config[0].nat_ip}"
  }
}

output "network_name" {
  description = "Name of the VPC network used"
  value       = var.create_vpc ? google_compute_network.ipfs_network[0].name : "default"
}

output "firewall_rule_name" {
  description = "Name of the firewall rule"
  value       = google_compute_firewall.ipfs_firewall.name
}

output "static_ip_addresses" {
  description = "Static IP addresses (if enabled)"
  value       = var.use_static_ip ? { for k, v in google_compute_address.ipfs_static_ip : k => v.address } : {}
}

output "instance_details" {
  description = "Detailed information about all instances"
  value = {
    for k, instance in google_compute_instance.ipfs_nodes : k => {
      name        = instance.name
      external_ip = instance.network_interface[0].access_config[0].nat_ip
      internal_ip = instance.network_interface[0].network_ip
      zone        = instance.zone
      region      = var.regions[k].region
      machine_type = instance.machine_type
      ssh_command = "gcloud compute ssh ${instance.name} --zone=${instance.zone} --project=${var.project_id}"
    }
  }
}

output "quick_start_instructions" {
  description = "Quick start instructions"
  value = <<-EOT
    ========================================
    IPFS Benchmark Infrastructure Created!
    ========================================

    ${length(google_compute_instance.ipfs_nodes)} instance(s) have been created across multiple regions.

    To connect to instances:
    ${join("\n    ", [for k, instance in google_compute_instance.ipfs_nodes : "# ${k}: gcloud compute ssh ${instance.name} --zone=${instance.zone} --project=${var.project_id}"])}

    After connecting, you can:
    1. The repository should be automatically cloned to ~/ipfs_bench
       cd ipfs_bench

    2. Start IPFS nodes with Docker:
       docker-compose up -d

    3. Apply network limitations:
       export BANDWIDTH_RATE="10mbit"
       export NETWORK_DELAY="50ms"
       sudo ./container-init/setup-router-tc.sh

    4. Run benchmarks:
       ./run_bench_10nodes.sh

    External IPs:
    ${join("\n    ", [for k, instance in google_compute_instance.ipfs_nodes : "${k} (${instance.name}): ${instance.network_interface[0].access_config[0].nat_ip}"])}

    To destroy infrastructure:
    terraform destroy

    ========================================
  EOT
}
