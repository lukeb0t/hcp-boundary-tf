terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.66.0"
    }
    boundary = {
      source = "hashicorp/boundary"
    }
    doormat = {
      source  = "doormat.hashicorp.services/hashicorp-security/doormat"
      version = ">= 0.0.3"
    }
  }
  cloud {
    organization = "argocorp"
    hostname = "app.terraform.io"

    workspaces {
      name = "hcp-boundary-tf"
    }
  }
}

provider "aws" {
  region = var.aws_region
  access_key = data.doormat_aws_credentials.creds.access_key
  secret_key = data.doormat_aws_credentials.creds.secret_key
  token      = data.doormat_aws_credentials.creds.token
  default_tags {
   tags = local.tags
}
}

locals {
  tags = {
    purpose            = "demo environment for Boundary and Vault",
    workspace          = var.TFC_WORKSPACE_NAME,
    slug               = var.TFC_WORKSPACE_SLUG
  }
}

provider "doormat" {}

data "doormat_aws_credentials" "creds" {
  provider = doormat
  role_arn = "arn:aws:iam::325038557378:role/hcp-boundary-tf"
}

provider "boundary" {
  addr = var.boundary_cluster_admin_url
  auth_method_id                  = var.boundary_auth_method_id
  password_auth_method_login_name = var.boundary_admin          
  password_auth_method_password   = var.boundary_admin_pw   
}

resource "random_pet" "unique_name" {
}

resource "random_integer" "unique_name" {
  min = 1000000
  max = 1999999
}

locals {
  unique_name = coalesce(var.unique_name, "${random_pet.unique_name.id}-${substr(random_integer.unique_name.result, -6, -1)}")
  admin_ip_result = "${var.admin_ip}/32"
  aws_instance_types = [ var.aws_k8s_node_instance_type, var.aws_postgres_node_instance_type, var.aws_vault_node_instance_type ]
  keypair = "${var.keypair_name != "" ? module.aws_infra.app_infra_ssh_privkey : var.keypair_name}"
}

module "aws_infra" {
  source = "./aws_infra"
  unique_name = local.unique_name
  admin_ip = local.admin_ip_result
  aws_region = var.aws_region
  aws_instance_types = local.aws_instance_types
  vpc_id = var.vpc_id
  igw_id = var.igw_id
  keypair_name = var.keypair_name
}

module "boundary_worker" {
  depends_on = [ module.aws_infra ]
  source = "./boundary_worker"
  unique_name = local.unique_name
  aws_region = var.aws_region
  vpc_id = var.vpc_id
  aws_ami = module.aws_infra.aws_ami_ubuntu
  aws_public_secgroup_id = module.aws_infra.aws_secgroup_public_id
  app_infra_ssh_privkey = local.keypair
  boundary_worker_instance_type = var.aws_boundary_worker_instance_type
  boundary_worker_subnet_id = module.aws_infra.aws_subnet_public_id
  boundary_cluster_admin_url = var.boundary_cluster_admin_url
}

module "postgres" {
  depends_on = [ module.aws_infra ]
  source = "./postgres"
  unique_name = local.unique_name
  aws_region = var.aws_region
  aws_ami = module.aws_infra.aws_ami_ubuntu
  pg_instance_type = var.aws_postgres_node_instance_type
  pg_subnet_id = module.aws_infra.aws_subnet_private_id
  pg_secgroup_id = module.aws_infra.aws_secgroup_private_id
  pg_ssh_keypair = local.keypair
}

module "k8s_cluster" {
  depends_on = [ module.aws_infra, module.boundary_worker ]
  source = "./k8s_cluster"
  unique_name = local.unique_name
  aws_region = var.aws_region
  vpc_id = var.vpc_id
  aws_ami = module.aws_infra.aws_ami_ubuntu
  boundary_cluster_admin_url = var.boundary_cluster_admin_url
  boundary_instance_worker_addr = "${module.boundary_worker.boundary_worker_dns_public}:9202"
  k8s_instance_type = var.aws_k8s_node_instance_type
  k8s_subnet_id = module.aws_infra.aws_subnet_private_id
  k8s_secgroup_id = module.aws_infra.aws_secgroup_private_id
  k8s_boundary_worker_lb_subnet_id = module.aws_infra.aws_subnet_public_id
  k8s_boundary_worker_lb_secgroup_id = module.aws_infra.aws_secgroup_public_id
  k8s_ssh_keypair = local.keypair #module.aws_infra.aws_ssh_keypair_app_infra
  k8s_nodeport_lb_vpc = var.vpc_id
}

module "vault_server" {
  depends_on = [ module.postgres, module.k8s_cluster ]
  source = "./vault_server"
  unique_name = local.unique_name
  aws_region = var.aws_region
  aws_ami = module.aws_infra.aws_ami_ubuntu
  vault_instance_type = var.aws_vault_node_instance_type
  vault_subnet_id = module.aws_infra.aws_subnet_private_id
  vault_secgroup_id = module.aws_infra.aws_secgroup_private_id
  vault_ssh_keypair = local.keypair #module.aws_infra.aws_ssh_keypair_app_infra
  vault_lb_vpc = var.vpc_id
  create_postgres = var.create_postgres
  postgres_server = module.postgres.dns
  pg_vault_user = module.postgres.vault_user
  pg_vault_password = module.postgres.vault_password
}

