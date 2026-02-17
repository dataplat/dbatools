function Import-DbaSpConfigure {
    <#
    .SYNOPSIS
        Copies sp_configure settings between SQL Server instances or applies settings from a SQL file.

    .DESCRIPTION
        Copies all sp_configure settings from a source SQL Server instance to a destination instance, or applies sp_configure settings from a SQL file to an instance. This function handles advanced options visibility, validates server versions for compatibility, and executes the necessary RECONFIGURE statements. Essential for maintaining consistent configuration across environments during migrations, standardization projects, or when applying saved configuration templates.

    .PARAMETER Source
        Source SQL Server instance to copy sp_configure settings from. Requires sysadmin privileges to read configuration values.
        Use this when migrating settings between servers or standardizing configurations across your environment.

    .PARAMETER Destination
        Target SQL Server instance where sp_configure settings will be applied. Requires sysadmin privileges to modify configuration.
        This server will have its configuration updated to match the source server's settings.

    .PARAMETER SourceSqlCredential
        Credentials for connecting to the source SQL Server instance. Use when Windows authentication is not available.
        Accepts PowerShell credential objects created with Get-Credential.

    .PARAMETER DestinationSqlCredential
        Credentials for connecting to the destination SQL Server instance. Use when Windows authentication is not available.
        Accepts PowerShell credential objects created with Get-Credential.

    .PARAMETER SqlInstance
        Specifies a SQL Server instance to set up sp_configure values on using a SQL file.

    .PARAMETER SqlCredential
        Use this SQL credential if you are setting up sp_configure values from a SQL file.

        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Path
        Path to a SQL script file containing sp_configure commands to execute. The file should contain individual sp_configure statements.
        Use this parameter when applying saved configurations from Export-DbaSpConfigure or custom configuration scripts.

    .PARAMETER Force
        Bypasses the SQL Server version compatibility check between source and destination instances. By default, major versions must match.
        Use with caution as some configuration options may not be available or may behave differently across SQL Server versions.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .NOTES
        Tags: SpConfig, Configure, Configuration
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Import-DbaSpConfigure

    .INPUTS
        None You cannot pipe objects to Import-DbaSpConfigure

    .OUTPUTS
        None

        This command does not generate any output. Configuration changes are applied directly to the destination SQL Server instance.

    .EXAMPLE
        PS C:\> Import-DbaSpConfigure -Source sqlserver -Destination sqlcluster

        Imports the sp_configure settings from the source server sqlserver and sets them on the sqlcluster server using Windows Authentication

    .EXAMPLE
        PS C:\> Import-DbaSpConfigure -Source sqlserver -Destination sqlcluster -Force

        Imports the sp_configure settings from the source server sqlserver and sets them on the sqlcluster server using Windows Authentication. Will not do a version check between Source and Destination

    .EXAMPLE
        PS C:\> Import-DbaSpConfigure -Source sqlserver -Destination sqlcluster -SourceSqlCredential $SourceSqlCredential -DestinationSqlCredential $DestinationSqlCredential

        Imports the sp_configure settings from the source server sqlserver and sets them on the sqlcluster server using the SQL credentials stored in the variables $SourceSqlCredential and $DestinationSqlCredential

    .EXAMPLE
        PS C:\> Import-DbaSpConfigure -SqlInstance sqlserver -Path .\spconfig.sql -SqlCredential $SqlCredential

        Imports the sp_configure settings from the file .\spconfig.sql and sets them on the sqlserver server using the SQL credential stored in the variable $SqlCredential

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [Parameter(ParameterSetName = "ServerCopy")]
        [DbaInstanceParameter]$Source,
        [Parameter(ParameterSetName = "ServerCopy")]
        [DbaInstanceParameter]$Destination,
        [Parameter(ParameterSetName = "ServerCopy")]
        [PSCredential]$SourceSqlCredential,
        [Parameter(ParameterSetName = "ServerCopy")]
        [PSCredential]$DestinationSqlCredential,
        [Parameter(ParameterSetName = "FromFile")]
        [DbaInstanceParameter]$SqlInstance,
        [Parameter(ParameterSetName = "FromFile")]
        [string]$Path,
        [Parameter(ParameterSetName = "FromFile")]
        [PSCredential]$SqlCredential,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if (-not $PSBoundParameters.Path -and $PSBoundParameters.Source) {
            try {
                $sourceserver = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
                return
            }

            if (-not (Test-SqlSa -SqlInstance $sourceserver -SqlCredential $SourceSqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $sourceserver. Quitting." -Category PermissionDenied -Target $server -Continue
            }

            try {
                $destserver = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination
                return
            }

            if (-not (Test-SqlSa -SqlInstance $destserver -SqlCredential $DestinationSqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $destserver. Quitting." -Category PermissionDenied -Target $server -Continue
            }

            $source = $sourceserver.DomainInstanceName
            $destination = $destserver.DomainInstanceName
        } else {
            try {
                $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance
                return
            }

            if (!(Test-SqlSa -SqlInstance $server -SqlCredential $SqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $server. Quitting." -Category PermissionDenied -Target $server -Continue
            }

            if (-not (Test-Path $Path)) {
                Stop-Function -Message "File $Path Not Found" -Category InvalidArgument -Target $Path -Continue
            }
        }

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if (-not $PSBoundParameters.Path) {
            if ($Pscmdlet.ShouldProcess($destination, "Export sp_configure")) {
                $sqlfilename = Export-DbaSpConfigure $sourceserver
            }

            if ($sourceserver.versionMajor -ne $destserver.versionMajor -and $force -eq $false) {
                Write-Message -Level Warning -Message "Source SQL Server major version and Destination SQL Server major version must match for sp_configure migration. Use -Force to override this precaution or check the exported sql file, $sqlfilename, and run manually."
                return
            }

            If ($Pscmdlet.ShouldProcess($destination, "Execute sp_configure")) {
                $sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
                $sourceserver.Configuration.Alter($true)
                $destserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
                $sourceserver.Configuration.Alter($true)

                $destprops = $destserver.Configuration.Properties

                foreach ($sourceprop in $sourceserver.Configuration.Properties) {
                    $displayname = $sourceprop.DisplayName

                    $destprop = $destprops | Where-Object { $_.Displayname -eq $displayname }
                    if ($null -ne $destprop) {
                        try {
                            $destprop.configvalue = $sourceprop.configvalue
                            $null = $destserver.Query("RECONFIGURE WITH OVERRIDE")
                            Write-Message -Level Output -Message "updated $($destprop.displayname) to $($sourceprop.configvalue)."
                        } catch {
                            Stop-Function -Message "Could not set $($destprop.displayname) to $($sourceprop.configvalue). Feature may not be supported." -ErrorRecord $_ -Continue
                        }
                    }
                }
                try {
                    $destserver.Configuration.Alter()
                } catch {
                    $needsrestart = $true
                }

                $sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
                $sourceserver.Configuration.Alter($true)
                $destserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
                $destserver.Configuration.Alter($true)

                if ($needsrestart -eq $true) {
                    Write-Message -Level Warning -Message "Some configuration options will be updated once SQL Server is restarted."
                } else {
                    Write-Message -Level Output -Message "Configuration option has been updated."
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Removing temp file")) {
                Remove-Item $sqlfilename -ErrorAction SilentlyContinue
            }

        } else {
            if ($Pscmdlet.ShouldProcess($destination, "Importing sp_configure from $Path")) {
                $server.Configuration.ShowAdvancedOptions.ConfigValue = $true
                $sql = Get-Content $Path
                foreach ($line in $sql) {
                    try {
                        $null = $server.Query($line)
                        Write-Message -Level Output -Message "Successfully executed $line."
                    } catch {
                        Stop-Function -Message "$line failed. Feature may not be supported." -ErrorRecord $_ -Continue
                    }
                }
                $server.Configuration.ShowAdvancedOptions.ConfigValue = $false
                Write-Message -Level Warning -Message "Some configuration options will be updated once SQL Server is restarted."
            }
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }

        if ($PSBoundParameters.Path) {
            $server.ConnectionContext.Disconnect()
        } else {
            $sourceserver.ConnectionContext.Disconnect()
            $destserver.ConnectionContext.Disconnect()
        }

        If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) {
            Write-Message -Level Output -Message "SQL Server configuration options migration finished."
        }
    }
}