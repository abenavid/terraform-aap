variable "aap_host" {
  description = "Automation Controller base URL (e.g. https://aap.example.com)"
  type        = string
}

variable "aap_username" {
  description = "AAP admin or service account username"
  type        = string
}

variable "aap_password" {
  description = "AAP password"
  type        = string
  sensitive   = true
}

variable "aap_insecure_skip_verify" {
  description = "Skip TLS verification (e.g. for self-signed certs)"
  type        = bool
  default     = false
}
