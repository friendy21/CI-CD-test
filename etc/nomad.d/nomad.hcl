# /etc/nomad.d/nomad.hcl
datacenter = "dc1"
data_dir = "/opt/nomad"

# Enable the server
server {
  enabled = true
  bootstrap_expect = 1  # Change to 3 for production cluster
  
  # Encryption key for gossip protocol (generate with: nomad operator keygen)
  encrypt = "YOUR_GOSSIP_ENCRYPTION_KEY"
}

# Enable the client (same machine for dev, separate for production)
client {
  enabled = true
  
  # Docker driver configuration
  options {
    "driver.docker.enable" = "true"
    "docker.privileged.enabled" = "true"
  }
  
  # Resource limits
  reserved {
    cpu    = 200
    memory = 512
  }
}

# Consul integration
consul {
  address = "127.0.0.1:8500"
  
  # Service discovery
  server_service_name = "nomad"
  client_service_name = "nomad-client"
  auto_advertise      = true
  
  # Checks
  server_auto_join = true
  client_auto_join = true
}

# Enable UI
ui {
  enabled = true
  
  # Consul integration for UI
  consul {
    ui_url = "http://127.0.0.1:8500/ui"
  }
}

# ACL configuration (for production)
acl {
  enabled = false  # Set to true for production
  token_ttl = "30s"
  policy_ttl = "60s"
}

# Telemetry
telemetry {
  collection_interval = "1s"
  disable_hostname = true
  prometheus_metrics = true
  publish_allocation_metrics = true
  publish_node_metrics = true
}

# TLS configuration (for production)
tls {
  http = false  # Set to true for production
  rpc  = false  # Set to true for production
  
  # ca_file   = "/etc/nomad.d/ca.pem"
  # cert_file = "/etc/nomad.d/server.pem"
  # key_file  = "/etc/nomad.d/server-key.pem"
}

# Autopilot for automatic cluster management
autopilot {
  cleanup_dead_servers      = true
  last_contact_threshold    = "200ms"
  max_trailing_logs         = 250
  server_stabilization_time = "10s"
}

# Enable raw_exec driver for non-containerized workloads (optional)
plugin "raw_exec" {
  config {
    enabled = false  # Set to true if needed
  }
}

# Configure log rotation
log_level = "INFO"
log_json = true
