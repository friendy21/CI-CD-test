# /etc/consul.d/consul.hcl
datacenter = "dc1"
data_dir = "/opt/consul"
log_level = "INFO"
node_name = "nomad-server-1"
server = true
bootstrap_expect = 1  # Change to 3 for production

ui_config {
  enabled = true
}

connect {
  enabled = true
}

ports {
  grpc = 8502
}

# ACL configuration (for production)
acl {
  enabled = false  # Set to true for production
  default_policy = "allow"
}

# Performance tuning
performance {
  raft_multiplier = 1
}
