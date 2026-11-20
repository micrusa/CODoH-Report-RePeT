terraform {
  required_version = ">= 1.5, < 2.0"
  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = "2.9.0"
    }
  }
}

provider "ibm" {
  alias  = "client"
  region = trimsuffix(var.nodes.client.zone, substr(var.nodes.client.zone, -2, 2))
}

provider "ibm" {
  alias  = "proxy"
  region = trimsuffix(var.nodes.proxy.zone, substr(var.nodes.proxy.zone, -2, 2))
}

provider "ibm" {
  alias  = "target"
  region = trimsuffix(var.nodes.target.zone, substr(var.nodes.target.zone, -2, 2))
}

variable "name_prefix" {
  type    = string
  default = "codoh"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,23}$", var.name_prefix))
    error_message = "Use up to 24 lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "resource_group_id" {
  type = string
}

variable "operator_cidr" {
  type        = string
  description = "Operator's public IPv4 address in /32 notation."
  validation {
    condition     = can(cidrnetmask(var.operator_cidr)) && endswith(var.operator_cidr, "/32")
    error_message = "Provide a single IPv4 address as a /32 CIDR."
  }
}

variable "ssh_public_key_file" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "existing_ssh_key_ids" {
  description = "Existing IBM VPC SSH key IDs by role. Each key must be in its VM's region."
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for role, id in var.existing_ssh_key_ids : contains(["client", "proxy", "target"], role) && try(trimspace(id) != "", false)])
    error_message = "Use client, proxy, or target with a nonempty SSH key ID."
  }
}

variable "enable_sgx" {
  type    = bool
  default = true
}

variable "nodes" {
  type = object({
    client = object({ zone = string, profile = string, image = string })
    proxy  = object({ zone = string, profile = string, image = string })
    target = object({ zone = string, profile = string, image = string })
  })
}

locals {
  public_key = trimspace(file(pathexpand(var.ssh_public_key_file)))
  nodes      = { client = module.client, proxy = module.proxy, target = module.target }

  # All paths cross regions over floating IPs. Each ingress rule admits one source.
  proxy_ports = {
    22    = module.client.ip
    8080  = module.client.ip
    9080  = module.client.ip
    10443 = module.client.ip
  }
  target_ports = merge(
    { for port in [22, 7443, 8443, 9443, 10444] : port => module.client.ip },
    { for port in [8443, 9443, 10444] : "proxy-${port}" => module.proxy.ip }
  )
}

module "client" {
  source              = "./node"
  providers           = { ibm = ibm.client }
  name                = "${var.name_prefix}-client"
  node                = var.nodes.client
  resource_group_id   = var.resource_group_id
  operator_cidr       = var.operator_cidr
  public_key          = local.public_key
  existing_ssh_key_id = lookup(var.existing_ssh_key_ids, "client", null)
}

module "proxy" {
  source              = "./node"
  providers           = { ibm = ibm.proxy }
  name                = "${var.name_prefix}-proxy"
  node                = var.nodes.proxy
  resource_group_id   = var.resource_group_id
  operator_cidr       = var.operator_cidr
  public_key          = local.public_key
  existing_ssh_key_id = lookup(var.existing_ssh_key_ids, "proxy", null)
  sgx                 = var.enable_sgx
}

module "target" {
  source              = "./node"
  providers           = { ibm = ibm.target }
  name                = "${var.name_prefix}-target"
  node                = var.nodes.target
  resource_group_id   = var.resource_group_id
  operator_cidr       = var.operator_cidr
  public_key          = local.public_key
  existing_ssh_key_id = lookup(var.existing_ssh_key_ids, "target", null)
}

resource "ibm_is_security_group_rule" "proxy_from_client" {
  provider  = ibm.proxy
  for_each  = local.proxy_ports
  group     = module.proxy.security_group
  direction = "inbound"
  remote    = "${each.value}/32"
  protocol  = "tcp"
  port_min  = tonumber(each.key)
  port_max  = tonumber(each.key)
}

resource "ibm_is_security_group_rule" "proxy_from_target" {
  provider  = ibm.proxy
  for_each  = var.enable_sgx ? toset(["8080", "8444"]) : toset(["8080"])
  group     = module.proxy.security_group
  direction = "inbound"
  remote    = "${module.target.ip}/32"
  protocol  = "tcp"
  port_min  = tonumber(each.key)
  port_max  = tonumber(each.key)
}

resource "ibm_is_security_group_rule" "attestation_probe" {
  provider  = ibm.proxy
  count     = var.enable_sgx ? 1 : 0
  group     = module.proxy.security_group
  direction = "inbound"
  remote    = "${module.client.ip}/32"
  protocol  = "tcp"
  port_min  = 8444
  port_max  = 8444
}

resource "ibm_is_security_group_rule" "target_from_peers" {
  provider  = ibm.target
  for_each  = local.target_ports
  group     = module.target.security_group
  direction = "inbound"
  remote    = "${each.value}/32"
  protocol  = "tcp"
  port_min  = tonumber(trimprefix(each.key, "proxy-"))
  port_max  = tonumber(trimprefix(each.key, "proxy-"))
}

output "hosts" {
  value = { for role, node in local.nodes : role => merge(var.nodes[role], { ip = node.ip }) }
}

output "enable_sgx" {
  value = var.enable_sgx
}
