# .aider Directory

This directory contains tools and scripts to help with upgrading and maintaining Pester tests within the dev container for the dbatools project.

## Contents

- `update-tests.ps1`: A PowerShell script to assist in upgrading Pester tests.

## Usage

### Upgrading Pester Tests

To upgrade Pester tests within the dev container:

1. Ensure you're working within the dev container environment.
2. Navigate to the root of the project.
3. Run the update-tests.ps1 script:

   ```powershell
   ./.aider/update-tests.ps1
   ```

This script will help automate the process of upgrading Pester tests to the latest version and syntax.

## Best Practices

- Always review the changes made by the update script before committing.
- Run the updated tests to ensure they still pass and cover all necessary scenarios.
- If you encounter any issues during the upgrade process, refer to the Pester documentation or seek assistance from the project maintainers.

## Contributing

If you improve the upgrade process or add new scripts to assist with test maintenance, please update this README accordingly.

For more information on contributing to dbatools, please refer to the main CONTRIBUTING.md file in the project root.
