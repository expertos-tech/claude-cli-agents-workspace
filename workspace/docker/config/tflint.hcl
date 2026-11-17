# Default TFLint config, used when a module has no .tflint.hcl of its own.
# Provider rulesets (azurerm) are added per project in its .tflint.hcl.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
