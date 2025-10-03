# Reference the dbatools repository
data "github_repository" "dbatools" {
  full_name = "${var.github_organization}/${var.github_repository}"
}

# Runner group removed - using default group for simplicity and self-healing
# Custom runner groups require org admin permissions and add unnecessary complexity
# for single-project setups. Runners will automatically use the "Default" group.
