# Infrastructure for Yandex Cloud Managed Service for Greenplum® cluster and Yandex Cloud Managed Service for ClickHouse
#
# RU: https://cloud.yandex.ru/docs/data-transfer/tutorials/greenplum-to-clickhouse
# EN: https://cloud.yandex.com/en/docs/data-transfer/tutorials/greenplum-to-clickhouse

# Specify the following settings
locals {
  gp_version   = "" # Set a Greenplum® version
  mgp_password = "" # Set a password for the Greenplum® user
  mch_db       = "" # Set а name for the ClickHouse database
  mch_user     = "" # Set а name for the ClickHouse database user
  mch_password = "" # Set a password for the ClickHouse database user
}

resource "yandex_vpc_network" "mgp_network" {
  description = "Network for Managed Service for Greenplum®"
  name        = "mgp_network"
}

resource "yandex_vpc_network" "mch_network" {
  description = "Network for Managed Service for ClickHouse"
  name        = "mch_network"
}

resource "yandex_vpc_subnet" "mgp_subnet-a" {
  description    = "Subnet in ru-central1-a availability zone for Greenplum®"
  name           = "mgp_subnet-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mgp_network.id
  v4_cidr_blocks = ["10.128.0.0/18"]
}

resource "yandex_vpc_subnet" "mch_subnet-a" {
  description    = "Subnet ru-central1-a availability zone for ClickHouse"
  name           = "mch_subnet-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.mch_network.id
  v4_cidr_blocks = ["10.129.0.0/24"]
}

resource "yandex_vpc_security_group" "mgp_security_group" {
  description = "Security group for Managed Service for Greenplum®"
  network_id  = yandex_vpc_network.mgp_network.id
  name        = "mgp_security_group"

  ingress {
    description    = "Allow incoming traffic from the Internet"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allow outgoing traffic to the Internet"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_vpc_security_group" "mch_security_group" {
  description = "Security group for Managed Service for ClickHouse"
  network_id  = yandex_vpc_network.mch_network.id
  name        = "mch_security_group"

  ingress {
    description    = "Allow incoming traffic from the port 8443"
    protocol       = "TCP"
    port           = 8443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow incoming traffic from the port 9440"
    protocol       = "TCP"
    port           = 9440
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allow outgoing traffic to the Internet"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_mdb_greenplum_cluster" "mgp-cluster" {
  description        = "Managed Service for Greenplum® cluster"
  name               = "mgp-cluster"
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.mgp_network.id
  zone               = "ru-central1-a"
  subnet_id          = yandex_vpc_subnet.mgp_subnet-a.id
  assign_public_ip   = true
  version            = local.gp_version
  master_host_count  = 2
  segment_host_count = 2
  segment_in_host    = 1
  master_subcluster {
    resources {
      resource_preset_id = "s2.medium" # 8 vCPU, 32 GB RAM
      disk_size          = 100         #GB
      disk_type_id       = "local-ssd"
    }
  }
  segment_subcluster {
    resources {
      resource_preset_id = "s2.medium" # 8 vCPU, 32 GB RAM
      disk_size          = 100         # GB
      disk_type_id       = "local-ssd"
    }
  }

  user_name     = "user"
  user_password = local.mgp_password

  security_group_ids = [yandex_vpc_security_group.mgp_security_group.id]
}

resource "yandex_mdb_clickhouse_cluster_v2" "mch-cluster" {
  description        = "Managed Service for ClickHouse cluster"
  name               = "mch-cluster"
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.mch_network.id
  security_group_ids = [yandex_vpc_security_group.mch_security_group.id]

  clickhouse = {
    resources = {
      resource_preset_id = "s2.micro"
      disk_type_id       = "network-ssd"
      disk_size          = 10 # GB
    }
  }

  hosts = {
    "ch-host1" = {
      type             = "CLICKHOUSE"
      zone             = "ru-central1-a"
      subnet_id        = yandex_vpc_subnet.mch_subnet-a.id
      assign_public_ip = true # Required for connection from the Internet
      shard_name       = "shard1"
    }
  }

  shards = {
    "shard1" = {}
  }

  maintenance_window {
    type = "ANYTIME"
  }
}

resource "yandex_mdb_clickhouse_database" "mch-db" {
  cluster_id = yandex_mdb_clickhouse_cluster_v2.mch-cluster.id
  name       = local.mch_db
}

resource "yandex_mdb_clickhouse_user" "mch-user" {
  cluster_id = yandex_mdb_clickhouse_cluster_v2.mch-cluster.id
  name       = local.mch_user
  password   = local.mch_password
  permission {
    database_name = yandex_mdb_clickhouse_database.mch-db.name
  }
  settings {
  }
}

resource "yandex_datatransfer_endpoint" "mch-target" {
  description = "Target endpoint for the Managed Service for ClickHouse cluster"
  name        = "mch-target"
  settings {
    clickhouse_target {
      connection {
        connection_options {
          mdb_cluster_id = yandex_mdb_clickhouse_cluster_v2.mch-cluster.id
          database       = local.mch_db
          user           = local.mch_user
          password {
            raw = local.mch_password
          }
        }
      }
      cleanup_policy = "CLICKHOUSE_CLEANUP_POLICY_DROP"
    }
  }
}
