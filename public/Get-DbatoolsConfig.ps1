function Get-DbatoolsConfig {
    <#
    .SYNOPSIS
        Retrieves dbatools module configuration settings and preferences.

    .DESCRIPTION
        Retrieves dbatools module configuration settings that control how dbatools functions behave. These settings include connection timeouts, default paths, email configurations, and other module preferences that affect dbatools operations. Use this command to view current settings, troubleshoot dbatools behavior, or identify what configurations are available for customization with Set-DbatoolsConfig.

    .PARAMETER FullName
        Default: "*"
        Specifies the complete configuration key in Module.Name format to retrieve specific dbatools settings.
        Use this to find exact configuration values like "sql.connection.timeout" or "mail.smtpserver" without needing to specify module and name separately.
        Supports wildcards for pattern matching across all configuration keys.

    .PARAMETER Name
        Default: "*"
        Specifies the configuration name to search for within a specific module.
        Use this with the Module parameter to find settings like "timeout" within the "sql" module or "smtpserver" within the "mail" module.
        Supports wildcards for finding multiple related configuration names.

    .PARAMETER Module
        Default: "*"
        Specifies which dbatools module's configuration settings to retrieve.
        Use this to focus on specific areas like "sql" for connection settings, "mail" for email configurations, or "path" for default file locations.
        Commonly used modules include sql, mail, path, and logging.

    .PARAMETER Force
        Includes hidden configuration values that are normally not displayed in the output.
        Use this when troubleshooting dbatools behavior or when you need to see internal configuration settings that control advanced module functionality.
        Hidden settings often include debugging flags and internal module state information.

    .OUTPUTS
        Dataplat.Dbatools.Configuration.Config

        Returns one Config object per setting found in the dbatools configuration system that matches the specified filter criteria. Results are sorted alphabetically by module name, then by configuration name.

        Properties:
        - Module: The module name component (e.g., "sql", "mail", "path", "logging")
        - Name: The configuration setting name within the module (e.g., "timeout", "smtpserver")
        - Value: The current value stored in the configuration setting (can be any object type)
        - Description: Human-readable description of what the configuration controls
        - Hidden: Boolean indicating if this is a hidden configuration setting

        When multiple settings match the filter criteria, each returns a separate object. The full configuration key is in "Module.Name" format (e.g., "sql.connection.timeout"). Hidden settings are excluded by default unless -Force is specified.

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