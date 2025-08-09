@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'aitools.psm1'

    # Version number of this module.
    ModuleVersion = '1.0.0'

    # Supported PSEditions
    CompatiblePSEditions = @('Desktop', 'Core')

    # ID used to uniquely identify this module
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'

    # Author of this module
    Author = 'dbatools team'

    # Company or vendor of this module
    CompanyName = 'dbatools'

    # Copyright statement for this module
    Copyright = '(c) 2025 dbatools team. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'AI-powered tools for dbatools development including pull request test repair, AppVeyor monitoring, and automated code quality fixes.'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules = @()

    # Assemblies that must be loaded prior to importing this module
    RequiredAssemblies = @()

    # Script files (.ps1) that are run in the caller's environment prior to importing this module.
    ScriptsToProcess = @()

    # Type files (.ps1xml) to be loaded when importing this module
    TypesToProcess = @()

    # Format files (.ps1xml) to be loaded when importing this module
    FormatsToProcess = @()

    # Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
    FunctionsToExport = @(
        'Repair-PullRequestTest',
        'Show-AppVeyorBuildStatus',
        'Get-AppVeyorFailure',
        'Update-PesterTest',
        'Invoke-AITool',
        'Invoke-AutoFix',
        'Repair-Error',
        'Repair-SmallThing',
        'Get-TestArtifact',
        'Get-TestArtifactContent'
    )

    # Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
    AliasesToExport = @()

    # Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. These help with module discovery in online galleries.
            Tags = @('dbatools', 'AI', 'Testing', 'Pester', 'CI', 'AppVeyor', 'Claude', 'Automation')

            # A URL to the license for this module.
            LicenseUri = 'https://opensource.org/licenses/MIT'

            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/dataplat/dbatools'

            # A URL to an icon representing this module.
            IconUri = ''

            # ReleaseNotes of this module
            ReleaseNotes = @'
# dbatools AI Tools v1.0.0

## Features
- **Repair-PullRequestTest**: Automatically fixes failing Pester tests in pull requests using Claude AI
- **Show-AppVeyorBuildStatus**: Displays detailed AppVeyor build status with colorful formatting
- **Get-AppVeyorFailures**: Retrieves and analyzes test failures from AppVeyor builds
- **Update-PesterTest**: Migrates Pester tests to v5 format using AI assistance
- **Invoke-AITool**: Unified interface for AI coding tools (Aider and Claude Code)
- **Invoke-AutoFix**: Automatically fixes PSScriptAnalyzer violations using AI
- **Repair-Error**: Repairs specific errors in test files using AI
- **Repair-SmallThing**: Fixes small issues in test files with predefined prompts

## Requirements
- PowerShell 5.1 or later
- GitHub CLI (gh)
- Git
- APPVEYOR_API_TOKEN environment variable (for AppVeyor features)
- AI tool access (Claude API or Aider installation)

## Installation
Import-Module ./.aitools/module/aitools.psd1
'@

            # Prerelease string of this module
            # Prerelease = ''

            # Flag to indicate whether the module requires explicit user acceptance for install/update/save
            # RequireLicenseAcceptance = $false

            # External dependent modules of this module
            # ExternalModuleDependencies = @()
        }
    }

    # HelpInfo URI of this module
    HelpInfoURI = 'https://docs.dbatools.io'

    # Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
    # DefaultCommandPrefix = ''
}