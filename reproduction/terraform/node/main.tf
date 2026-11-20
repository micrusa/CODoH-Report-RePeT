terraform {
  required_providers {
    ibm = { source = "IBM-Cloud/ibm" }
  }
}

variable "name" {
  type = string
}

variable "node" {
  type = object({ zone = string, profile = string, image = string })
}

variable "resource_group_id" {
  type = string
}

variable "operator_cidr" {
  type = string
}

variable "public_key" {
  type = string
}

variable "existing_ssh_key_id" {
  type    = string
  default = null
}

variable "sgx" {
  type    = bool
  default = false
}

data "ibm_is_image" "ubuntu" {
  name = var.node.image
}

resource "ibm_is_vpc" "node" {
  name           = var.name
  resource_group = var.resource_group_id
}

resource "ibm_is_subnet" "node" {
  name                     = var.name
  vpc                      = ibm_is_vpc.node.id
  zone                     = var.node.zone
  total_ipv4_address_count = 32
  resource_group           = var.resource_group_id
}

resource "ibm_is_security_group" "node" {
  name           = var.name
  vpc            = ibm_is_vpc.node.id
  resource_group = var.resource_group_id
}

resource "ibm_is_security_group_rule" "ssh" {
  group     = ibm_is_security_group.node.id
  direction = "inbound"
  remote    = var.operator_cidr
  protocol  = "tcp"
  port_min  = 22
  port_max  = 22
}

resource "ibm_is_security_group_rule" "egress" {
  group     = ibm_is_security_group.node.id
  direction = "outbound"
  remote    = "0.0.0.0/0"
}

resource "ibm_is_ssh_key" "operator" {
  count          = var.existing_ssh_key_id == null ? 1 : 0
  name           = var.name
  public_key     = var.public_key
  resource_group = var.resource_group_id
}

moved {
  from = ibm_is_ssh_key.operator
  to   = ibm_is_ssh_key.operator[0]
}

resource "ibm_is_instance" "node" {
  name                      = var.name
  vpc                       = ibm_is_vpc.node.id
  zone                      = var.node.zone
  profile                   = var.node.profile
  image                     = data.ibm_is_image.ubuntu.id
  resource_group            = var.resource_group_id
  keys                      = var.existing_ssh_key_id == null ? [ibm_is_ssh_key.operator[0].id] : [var.existing_ssh_key_id]
  confidential_compute_mode = var.sgx ? "sgx" : null

  primary_network_interface {
    subnet          = ibm_is_subnet.node.id
    security_groups = [ibm_is_security_group.node.id]
  }

  depends_on = [ibm_is_security_group_rule.ssh, ibm_is_security_group_rule.egress]
}

resource "ibm_is_floating_ip" "node" {
  name           = var.name
  target         = ibm_is_instance.node.primary_network_interface[0].id
  resource_group = var.resource_group_id
}

output "ip" {
  value = ibm_is_floating_ip.node.address
}

output "security_group" {
  value = ibm_is_security_group.node.id
}
