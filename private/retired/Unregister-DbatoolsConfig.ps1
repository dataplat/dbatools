function Unregister-DbatoolsConfig {
    <#
    .SYNOPSIS
        Removes persisted dbatools configuration settings from registry and configuration files.

    .DESCRIPTION
        Removes dbatools configuration settings that have been persisted to Windows registry or JSON configuration files. This lets you clean up module settings that were previously saved using Register-DbatoolsConfig, removing them from user profiles or system-wide storage locations.

        The function handles settings stored in multiple persistence scopes including user-specific registry entries, computer-wide registry settings, and JSON configuration files in various user and system directories. You can target specific settings by name or module, or remove entire configuration groups.

        Note: This command only removes persisted settings and has no effect on configuration values currently loaded in PowerShell memory.

    .PARAMETER ConfigurationItem
        Specifies configuration objects to remove from persistent storage, as returned by Get-DbatoolsConfig.
        Use this when you want to unregister specific settings already identified through Get-DbatoolsConfig.

    .PARAMETER FullName
        Specifies the complete name of the configuration setting to remove from persistent storage.
        Use this when you know the exact setting name in the format 'module.category.setting'.

    .PARAMETER Module
        Specifies the module name to target for configuration removal.
        Use this to remove all configuration settings belonging to a specific dbatools module or component.

    .PARAMETER Name
        Specifies the setting name pattern to match within the targeted module. Supports wildcards.
        Use with the Module parameter to narrow down which settings to remove, defaults to '*' to match all settings.

    .PARAMETER Scope
        Specifies which configuration storage locations to target for removal: user settings, computer-wide settings, or file-based configurations.
        Defaults to UserDefault which removes settings from the current user's registry. Use SystemDefault to remove computer-wide settings (requires elevation).

    .NOTES
        Tags: Module
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .OUTPUTS
        None

        This command does not return any output objects. It removes persisted configuration settings from registry and configuration files based on the specified parameters.

    .LINK
        https://dbatools.io/Unregister-DbatoolsConfig

    .EXAMPLE
        PS C:\> Get-DbatoolsConfig | Unregister-DbatoolsConfig

        Completely removes all registered configurations currently loaded in memory.
        In most cases, this will mean removing all registered configurations.

    .EXAMPLE
        PS C:\> Unregister-DbatoolsConfig -Scope SystemDefault -FullName 'MyModule.Path.DefaultExport'

        Unregisters the setting 'MyModule.Path.DefaultExport' from the list of computer-wide defaults.
        Note: Changing system wide settings requires running the console with elevation.

    .EXAMPLE
        PS C:\> Unregister-DbatoolsConfig -Module MyModule

        Unregisters all configuration settings for the module MyModule.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    param (
        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'Pipeline')]
        [Dataplat.Dbatools.Configuration.Config[]]
        $ConfigurationItem,

        [Parameter(ValueFromPipeline = $true, ParameterSetName = 'Pipeline')]
        [string[]]
        $FullName,

        [Parameter(Mandatory = $true, ParameterSetName = 'Module')]
        [string]
        $Module,

        [Parameter(ParameterSetName = 'Module')]
        [string]
        $Name = "*",

        [Dataplat.Dbatools.Configuration.ConfigScope]
        $Scope = "UserDefault"
    )

    begin {
        if (($PSVersionTable.PSVersion.Major -ge 6) -and ($PSVersionTable.OS -notlike "*Windows*") -and ($Scope -band 15)) {
            Stop-Function -Message "Cannot unregister configurations from registry on non-windows machines." -Tag 'NotSupported' -Category ResourceUnavailable
            return
        }

        #region Initialize Collection
        $registryProperties = @()
        if ($Scope -band 1) {
            if (Test-Path $script:path_RegistryUserDefault) { $registryProperties += Get-ItemProperty -Path $script:path_RegistryUserDefault }
        }
        if ($Scope -band 2) {
            if (Test-Path $script:path_RegistryUserEnforced) { $registryProperties += Get-ItemProperty -Path $script:path_RegistryUserEnforced }
        }
        if ($Scope -band 4) {
            if (Test-Path $script:path_RegistryMachineDefault) { $registryProperties += Get-ItemProperty -Path $script:path_RegistryMachineDefault }
        }
        if ($Scope -band 8) {
            if (Test-Path $script:path_RegistryMachineEnforced) { $registryProperties += Get-ItemProperty -Path $script:path_RegistryMachineEnforced }
        }
        $pathProperties = @()
        if ($Scope -band 16) {
            $fileUserLocalSettings = @()
            if (Test-Path (Join-Path $script:path_FileUserLocal "psf_config.json")) { $fileUserLocalSettings = Get-Content (Join-Path $script:path_FileUserLocal "psf_config.json") -Encoding UTF8 | ConvertFrom-Json }
            if ($fileUserLocalSettings) {
                $pathProperties += [PSCustomObject]@{
                    Path       = (Join-Path $script:path_FileUserLocal "psf_config.json")
                    Properties = $fileUserLocalSettings
                    Changed    = $false
                }
            }
        }
        if ($Scope -band 32) {
            $fileUserSharedSettings = @()
            if (Test-Path (Join-Path $script:path_FileUserShared "psf_config.json")) { $fileUserSharedSettings = Get-Content (Join-Path $script:path_FileUserShared "psf_config.json") -Encoding UTF8 | ConvertFrom-Json }
            if ($fileUserSharedSettings) {
                $pathProperties += [PSCustomObject]@{
                    Path       = (Join-Path $script:path_FileUserShared "psf_config.json")
                    Properties = $fileUserSharedSettings
                    Changed    = $false
                }
            }
        }
        if ($Scope -band 64) {
            $fileSystemSettings = @()
            if (Test-Path (Join-Path $script:path_FileSystem "psf_config.json")) { $fileSystemSettings = Get-Content (Join-Path $script:path_FileSystem "psf_config.json") -Encoding UTF8 | ConvertFrom-Json }
            if ($fileSystemSettings) {
                $pathProperties += [PSCustomObject]@{
                    Path       = (Join-Path $script:path_FileSystem "psf_config.json")
                    Properties = $fileSystemSettings
                    Changed    = $false
                }
            }
        }
        #endregion Initialize Collection

        $common = 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider'
    }
    process {
        if (Test-FunctionInterrupt) { return }
        # Silently skip since no action necessary
        if (-not ($pathProperties -or $registryProperties)) { return }

        foreach ($item in $ConfigurationItem) {
            # Registry
            foreach ($hive in ($registryProperties | Where-Object { $_.PSObject.Properties.Name -eq $item.FullName })) {
                Remove-ItemProperty -Path $hive.PSPath -Name $item.FullName
            }
            # Prepare file
            foreach ($fileConfig in ($pathProperties | Where-Object { $_.Properties.FullName -contains $item.FullName })) {
                $fileConfig.Properties = $fileConfig.Properties | Where-Object FullName -NE $item.FullName
                $fileConfig.Changed = $true
            }
        }

        foreach ($item in $FullName) {
            # Ignore string-casted configurations
            if ($item -ceq "Dataplat.Dbatools.Configuration.Config") { continue }

            # Registry
            foreach ($hive in ($registryProperties | Where-Object { $_.PSObject.Properties.Name -eq $item })) {
                Remove-ItemProperty -Path $hive.PSPath -Name $item
            }
            # Prepare file
            foreach ($fileConfig in ($pathProperties | Where-Object { $_.Properties.FullName -contains $item })) {
                $fileConfig.Properties = $fileConfig.Properties | Where-Object FullName -NE $item
                $fileConfig.Changed = $true
            }
        }

        if ($Module) {
            $compoundName = "{0}.{1}" -f $Module, $Name

            # Registry
            foreach ($hive in ($registryProperties | Where-Object { $_.PSObject.Properties.Name -like $compoundName })) {
                foreach ($propName in $hive.PSObject.Properties.Name) {
                    if ($propName -in $common) { continue }

                    if ($propName -like $compoundName) {
                        Remove-ItemProperty -Path $hive.PSPath -Name $propName
                    }
                }
            }
            # Prepare file
            foreach ($fileConfig in ($pathProperties | Where-Object { $_.Properties.FullName -like $compoundName })) {
                $fileConfig.Properties = $fileConfig.Properties | Where-Object FullName -NotLike $compoundName
                $fileConfig.Changed = $true
            }
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }

        foreach ($fileConfig in $pathProperties) {
            if (-not $fileConfig.Changed) { continue }

            if ($fileConfig.Properties) {
                $fileConfig.Properties | ConvertTo-Json | Set-Content -Path $fileConfig.Path -Encoding UTF8
            } else {
                Remove-Item $fileConfig.Path
            }
        }
    }
}