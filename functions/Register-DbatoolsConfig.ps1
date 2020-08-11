function Register-DbatoolsConfig {
    <#
    .SYNOPSIS
        Registers an existing configuration object in registry.

    .DESCRIPTION
        Registers an existing configuration object in registry.
        This allows simple persisting of settings across powershell consoles.
        It also can be used to generate a registry template, which can then be used to create policies.

    .PARAMETER Config
        The configuration object to write to registry.
        Can be retrieved using Get-DbatoolsConfig.

    .PARAMETER FullName
        The full name of the setting to be written to registry.

    .PARAMETER Module
        The name of the module, whose settings should be written to registry.

    .PARAMETER Name
        Default: "*"
        Used in conjunction with the -Module parameter to restrict the number of configuration items written to registry.

    .PARAMETER Scope
        Default: UserDefault
        Who will be affected by this export how? Current user or all? Default setting or enforced?
        Legal values: UserDefault, UserMandatory, SystemDefault, SystemMandatory

    .PARAMETER EnableException
        This parameters disables user-friendly warnings and enables the throwing of exceptions.
        This is less user friendly, but allows catching exceptions in calling scripts.

    .NOTES
        Tags: Module
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Register-DbatoolsConfig

    .EXAMPLE
        PS C:\> Get-DbatoolsConfig message.style.* | Register-DbatoolsConfig

        Retrieves all configuration items that that start with message.style. and registers them in registry for the current user.

    .EXAMPLE
        PS C:\> Register-DbatoolsConfig -FullName "message.consoleoutput.disable" -Scope SystemDefault

        Retrieves the configuration item "message.consoleoutput.disable" and registers it in registry as the default setting for all users on this machine.

    .EXAMPLE
        PS C:\> Register-DbatoolsConfig -Module Message -Scope SystemMandatory

        Retrieves all configuration items of the module Message, then registers them in registry to enforce them for all users on the current system.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    Param (
        [Parameter(ParameterSetName = "Default", ValueFromPipeline = $true)]
        [Sqlcollaborative.Dbatools.Configuration.Config[]]
        $Config,

        [Parameter(ParameterSetName = "Default", ValueFromPipeline = $true)]
        [string[]]
        $FullName,

        [Parameter(Mandatory = $true, ParameterSetName = "Name", Position = 0)]
        [string]
        $Module,

        [Parameter(ParameterSetName = "Name", Position = 1)]
        [string]
        $Name = "*",

        [Sqlcollaborative.Dbatools.Configuration.ConfigScope]
        $Scope = "UserDefault",

        [switch]$EnableException
    )

    begin {
        if ($script:NoRegistry -and ($Scope -band 14)) {
            Stop-Function -Message "Cannot register configurations on non-windows machines to registry. Please specify a file-based scope" -Tag 'NotSupported' -Category NotImplemented
            return
        }

        # Linux and MAC default to local user store file
        if ($script:NoRegistry -and ($Scope -eq "UserDefault")) {
            $Scope = [Sqlcollaborative.Dbatools.Configuration.ConfigScope]::FileUserLocal
        }
        # Linux and MAC get redirection for SystemDefault to FileSystem
        if ($script:NoRegistry -and ($Scope -eq "SystemDefault")) {
            $Scope = [Sqlcollaborative.Dbatools.Configuration.ConfigScope]::FileSystem
        }

        $parSet = $PSCmdlet.ParameterSetName

        function Write-Config {
            [CmdletBinding()]
            Param (
                [Sqlcollaborative.Dbatools.Configuration.Config]
                $Config,

                [Sqlcollaborative.Dbatools.Configuration.ConfigScope]
                $Scope,

                [bool]
                $EnableException,

                [string]
                $FunctionName = (Get-PSCallStack)[0].Command
            )

            if (-not $Config -or ($Config.RegistryData -eq "<type not supported>")) {
                Stop-Function -Message "Invalid Input, cannot export $($Config.FullName), type not supported" -EnableException $EnableException -Category InvalidArgument -Tag "config", "fail" -Target $Config -FunctionName $FunctionName
                return
            }

            try {
                Write-Message -Level Verbose -Message "Registering $($Config.FullName) for $Scope" -Tag "Config" -Target $Config -FunctionName $FunctionName
                #region User Default
                if (1 -band $Scope) {
                    Ensure-RegistryPath -Path $script:path_RegistryUserDefault -ErrorAction Stop
                    Set-ItemProperty -Path $script:path_RegistryUserDefault -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion User Default

                #region User Mandatory
                if (2 -band $Scope) {
                    Ensure-RegistryPath -Path $script:path_RegistryUserEnforced -ErrorAction Stop
                    Set-ItemProperty -Path $script:path_RegistryUserEnforced -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion User Mandatory

                #region System Default
                if (4 -band $Scope) {
                    Ensure-RegistryPath -Path $script:path_RegistryMachineDefault -ErrorAction Stop
                    Set-ItemProperty -Path $script:path_RegistryMachineDefault -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion System Default

                #region System Mandatory
                if (8 -band $Scope) {
                    Ensure-RegistryPath -Path $script:path_RegistryMachineEnforced -ErrorAction Stop
                    Set-ItemProperty -Path $script:path_RegistryMachineEnforced -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion System Mandatory
            } catch {
                Stop-Function -Message "Failed to export $($Config.FullName), to scope $Scope" -EnableException $EnableException -Tag "config", "fail" -Target $Config -ErrorRecord $_ -FunctionName $FunctionName
                return
            }
        }

        function Ensure-RegistryPath {
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "")]
            [CmdletBinding()]
            Param (
                [string]
                $Path
            )

            if (-not (Test-Path $Path)) {
                $null = New-Item $Path -Force
            }
        }

        # For file based persistence
        $configurationItems = @()
    }
    process {
        if (Test-FunctionInterrupt) { return }

        #region Registry Based
        if ($Scope -band 15) {
            switch ($parSet) {
                "Default" {
                    foreach ($item in $Config) {
                        Write-Config -Config $item -Scope $Scope -EnableException $EnableException
                    }

                    foreach ($item in $FullName) {
                        if ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.ContainsKey($item.ToLowerInvariant())) {
                            Write-Config -Config ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations[$item.ToLowerInvariant()]) -Scope $Scope -EnableException $EnableException
                        }
                    }
                }
                "Name" {
                    foreach ($item in ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.Values | Where-Object Module -EQ $Module | Where-Object Name -Like $Name)) {
                        Write-Config -Config $item -Scope $Scope -EnableException $EnableException
                    }
                }
            }
        }
        #endregion Registry Based

        #region File Based
        else {
            switch ($parSet) {
                "Default" {
                    foreach ($item in $Config) {
                        if ($configurationItems.FullName -notcontains $item.FullName) { $configurationItems += $item }
                    }

                    foreach ($item in $FullName) {
                        if (($configurationItems.FullName -notcontains $item) -and ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.ContainsKey($item.ToLowerInvariant()))) {
                            $configurationItems += [Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations[$item.ToLowerInvariant()]
                        }
                    }
                }
                "Name" {
                    foreach ($item in ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.Values | Where-Object Module -EQ $Module | Where-Object Name -Like $Name)) {
                        if ($configurationItems.FullName -notcontains $item.FullName) { $configurationItems += $item }
                    }
                }
            }
        }
        #endregion File Based
    }
    end {
        if (Test-FunctionInterrupt) { return }

        #region Finish File Based Persistence
        if ($Scope -band 16) {
            Write-DbatoolsConfigFile -Config $configurationItems -Path (Join-Path $script:path_FileUserLocal "psf_config.json")
        }
        if ($Scope -band 32) {
            Write-DbatoolsConfigFile -Config $configurationItems -Path (Join-Path $script:path_FileUserShared "psf_config.json")
        }
        if ($Scope -band 64) {
            Write-DbatoolsConfigFile -Config $configurationItems -Path (Join-Path $script:path_FileSystem "psf_config.json")
        }
        #endregion Finish File Based Persistence
    }
}