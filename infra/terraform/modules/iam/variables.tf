# Input contract for the IAM module.
#
# The module is written so it is not hardcoded to the dev environment.
# The caller passes a name prefix, and every resource name is built from
# it. This is what lets the same module build IAM for dev, staging, or
# any other environment without editing the module itself.

variable "name_prefix" {
  description = "Prefix for all IAM resource names, e.g. platform10-dev. Every resource in this module is named with this prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must be lowercase letters, numbers, and hyphens only."
  }
}
