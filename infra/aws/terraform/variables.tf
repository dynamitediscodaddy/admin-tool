variable "region" {
  type    = string
  default = "eusc-de-east-1"
}
variable "name" {
  type    = string
  default = "admin-tool-demo"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,24}$", var.name))
    error_message = "Use 3–25 lowercase letters, digits or hyphens, starting with a letter."
  }
}
variable "enable_service" {
  type        = bool
  default     = true
  description = "False only for the initial registry bootstrap before images are pushed."
}
variable "image_tag" {
  type    = string
  default = "initial"
}
variable "domain_name" {
  type     = string
  default  = null
  nullable = true
}
variable "hosted_zone_id" {
  type     = string
  default  = null
  nullable = true
}
