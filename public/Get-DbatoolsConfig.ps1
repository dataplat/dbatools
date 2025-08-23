function Get-DbatoolsConfig {
    <#
    .SYNOPSIS
        Retrieves dbatools module configuration settings and preferences.

    .DESCRIPTION
        Retrieves dbatools module configuration settings that control how dbatools functions behave. These settings include connection timeouts, default paths, email configurations, and other module preferences that affect dbatools operations. Use this command to view current settings, troubleshoot dbatools behavior, or identify what configurations are available for customization with Set-DbatoolsConfig.

    .PARAMETER FullName
        Default: "*"
        Search for configurations using the full name

    .PARAMETER Name
        Default: "*"
        The name of the configuration element(s) to retrieve.
        May be any string, supports wildcards.

    .PARAMETER Module
        Default: "*"
        Search configuration by module.

    .PARAMETER Force
        Overrides the default behavior and also displays hidden configuration values.

    .NOTES
        Tags: Module
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbatoolsConfig

    .EXAMPLE
        PS C:\> Get-DbatoolsConfig 'Mail.To'

        Retrieves the configuration element for the key "Mail.To"

    .EXAMPLE
        PS C:\> Get-DbatoolsConfig -Force

        Retrieve all configuration elements from all modules, even hidden ones.
    #>
    [CmdletBinding(DefaultParameterSetName = "FullName")]
    param (
        [Parameter(ParameterSetName = "FullName", Position = 0)]
        [string]$FullName = "*",
        [Parameter(ParameterSetName = "Module", Position = 1)]
        [string]$Name = "*",
        [Parameter(ParameterSetName = "Module", Position = 0)]
        [string]$Module = "*",
        [switch]$Force
    )

    switch ($PSCmdlet.ParameterSetName) {
        "Module" {
            $Name = $Name.ToLowerInvariant()
            $Module = $Module.ToLowerInvariant()

            [Dataplat.Dbatools.Configuration.ConfigurationHost]::Configurations.Values | Where-Object { ($_.Name -like $Name) -and ($_.Module -like $Module) -and ((-not $_.Hidden) -or ($Force)) } | Sort-Object Module, Name
        }

        "FullName" {
            [Dataplat.Dbatools.Configuration.ConfigurationHost]::Configurations.Values | Where-Object { ("$($_.Module).$($_.Name)" -like $FullName) -and ((-not $_.Hidden) -or ($Force)) } | Sort-Object Module, Name
        }
    }
}