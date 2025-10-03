# Reference the dbatools repository
data "github_repository" "dbatools" {
  full_name = "${var.github_organization}/${var.github_repository}"
}

# Create a runner group for VMSS runners
resource "github_actions_runner_group" "vmss" {
  name                       = "azure-vmss-runners"
  visibility                 = "selected"
  selected_repository_ids    = [data.github_repository.dbatools.repo_id]
  allows_public_repositories = false
}
