# cicd-app.nomad
job "cicd-app" {
  datacenters = ["dc1"]
  type = "service"
  
  # Update strategy
  update {
    max_parallel      = 1
    min_healthy_time  = "30s"
    healthy_deadline  = "3m"
    progress_deadline = "10m"
    auto_revert       = true
    canary           = 1
  }
  
  # Migration strategy
  migrate {
    max_parallel = 1
    health_check = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }
  
  # Task group
  group "web" {
    count = 3  # Number of instances
    
    # Spread across nodes (if multiple nodes)
    spread {
      attribute = "${node.unique.id}"
    }
    
    # Rolling restart
    restart {
      attempts = 2
      interval = "30m"
      delay = "15s"
      mode = "fail"
    }
    
    # Ephemeral disk
    ephemeral_disk {
      size = 300
    }
    
    # Network configuration
    network {
      port "http" {
        to = 3000
      }
    }
    
    # Service registration with Consul
    service {
      name = "cicd-app"
      tags = ["web", "nodejs", "urlprefix-/"]
      port = "http"
      
      # Health check
      check {
        name     = "alive"
        type     = "http"
        path     = "/health"
        interval = "10s"
        timeout  = "2s"
      }
      
      # Service mesh (optional)
      connect {
        sidecar_service {}
      }
    }
    
    # Main task
    task "app" {
      driver = "docker"
      
      # Docker configuration
      config {
        image = "docker.io/friendy21/cicd-nomad-app:latest"
        ports = ["http"]
        
        # Authentication
        auth {
          username = "${DOCKER_USERNAME}"
          password = "${DOCKER_TOKEN}"
        }
        
        # Resource limits
        memory_hard_limit = 512
        
        # Security options
        cap_drop = ["ALL"]
        cap_add = ["NET_BIND_SERVICE"]
        readonly_rootfs = true
        security_opt = ["no-new-privileges"]
        
        # Health check
        healthchecks {
          disable = false
        }
        
        # Logging
        logging {
          type = "json-file"
          config {
            max-size = "10m"
            max-file = "3"
          }
        }
      }
      
      # Environment variables
      env {
        NODE_ENV = "production"
        PORT = "3000"
        LOG_LEVEL = "${meta.log_level}"
      }
      
      # Template for dynamic configuration
      template {
        data = <<EOH
# Dynamic configuration from Consul
{{ range service "database" }}
DATABASE_HOST={{ .Address }}
DATABASE_PORT={{ .Port }}
{{ end }}
EOH
        destination = "secrets/db.env"
        env = true
      }
      
      # Resource limits
      resources {
        cpu    = 100  # MHz
        memory = 256  # MB
      }
      
      # Kill timeout
      kill_timeout = "30s"
      
      # Log configuration
      logs {
        max_files     = 10
        max_file_size = 15
      }
      
      # Vault integration (optional)
      vault {
        policies = ["cicd-app"]
        change_mode = "restart"
      }
    }
    
    # Sidecar task for monitoring (optional)
    task "prometheus-exporter" {
      driver = "docker"
      
      lifecycle {
        hook = "prestart"
        sidecar = true
      }
      
      config {
        image = "prom/node-exporter:latest"
        ports = ["metrics"]
      }
      
      resources {
        cpu = 50
        memory = 32
      }
    }
  }
}
