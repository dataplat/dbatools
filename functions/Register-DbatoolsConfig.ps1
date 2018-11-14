function Register-DbatoolsConfig {
    <#
    .SYNOPSIS
        Registers an existing configuration object in registry.

    .DESCRIPTION
        Registers an existing configuration object in registry.
        This allows simple persisting of settings across powershell consoles.
        It also can be used to generate a registry template, which can then be used to create policies.

    .PARAMETER Config
        The configuration object to write to registry. Can be retrieved using Get-DbatoolsConfig.

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
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Config, Module
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .EXAMPLE
        PS C:\> Get-DbatoolsConfig message.* | Register-DbatoolsConfig

        Retrieves all configuration items that that start with message. and registers them in registry for the current user.

    .EXAMPLE
        PS C:\> Register-DbatoolsConfig -FullName "developer.mode.enable" -Scope SystemDefault

        Retrieves the configuration item "developer.mode.enable" and registers it in registry as the default setting for all users on this machine.

    .EXAMPLE
        PS C:\> Register-DbatoolsConfig -Module message -Scope SystemMandatory

        Retrieves all configuration items of the module MyModule, then registers them in registry to enforce them for all users on the current system.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "", Justification = "Internal functions are ignored")]
    param (
        [Parameter(ParameterSetName = "Default", Position = 0, ValueFromPipeline)]
        [Sqlcollaborative.Dbatools.Configuration.Config[]]$Config,
        [Parameter(ParameterSetName = "Default", Position = 0, ValueFromPipeline)]
        [string[]]$FullName,
        [Parameter(Mandatory, ParameterSetName = "Name", Position = 0)]
        [string]$Module,
        [Parameter(ParameterSetName = "Name", Position = 1)]
        [string]$Name = "*",
        [Sqlcollaborative.Dbatools.Configuration.ConfigScope]$Scope = "UserDefault",
        [switch]$EnableException
    )

    begin {
        $parSet = $PSCmdlet.ParameterSetName

        function Write-Config {
            [CmdletBinding()]
            param (
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
                Stop-Function -Message "Invalid Input, cannot export $($Config.FullName), type not supported" -EnableException $EnableException -Category InvalidArgument -Target $Config -FunctionName $FunctionName #-ModuleName "PSFramework" -Tag "config", "fail"
                return
            }

            try {
                Write-Message -Level Verbose -Message "Registering $($Config.FullName) for $Scope" -Target $Config -FunctionName $FunctionName #-ModuleName "PSFramework" -Tag "Config"
                #region User Default
                if (1 -band $Scope) {
                    Ensure-RegistryPath -Path "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Default" -ErrorAction Stop
                    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Default" -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion User Default

                #region User Mandatory
                if (2 -band $Scope) {
                    Ensure-RegistryPath -Path "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Enforced" -ErrorAction Stop
                    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Enforced" -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion User Mandatory

                #region System Default
                if (4 -band $Scope) {
                    Ensure-RegistryPath -Path "HKLM:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Default" -ErrorAction Stop
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Default" -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion System Default

                #region System Mandatory
                if (8 -band $Scope) {
                    Ensure-RegistryPath -Path "HKLM:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Enforced" -ErrorAction Stop
                    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WindowsPowerShell\dbatools\Config\Enforced" -Name $Config.FullName -Value $Config.RegistryData -ErrorAction Stop
                }
                #endregion System Mandatory
            } catch {
                Stop-Function -Message "Failed to export $($Config.FullName), to scope $Scope" -EnableException $EnableException -Target $Config -ErrorRecord $_ -FunctionName $FunctionName #-ModuleName "PSFramework" -Tag "config", "fail"
                return
            }
        }

        function Ensure-RegistryPath {
            [CmdletBinding()]
            param (
                [string]
                $Path
            )

            if (-not (Test-Path $Path)) {
                $null = New-Item $Path -Force -ErrorAction Stop
            }
        }
    }
    process {
        switch ($parSet) {
            "Default" {
                foreach ($item in $Config) {
                    Write-Config -Config $item -Scope $Scope -EnableException $EnableException
                }

                foreach ($item in $FullName) {
                    if ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations.ContainsKey($item.ToLower())) {
                        Write-Config -Config ([Sqlcollaborative.Dbatools.Configuration.ConfigurationHost]::Configurations[$item.ToLower()]) -Scope $Scope -EnableException $EnableException
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
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Register-DbaConfig
    }
}