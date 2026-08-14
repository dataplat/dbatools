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

        This command writes no objects to the pipeline. Progress is reported as messages: one per configuration option that was changed, and a final message when the migration is finished.

        A warning is written when an option could not be set on the destination, and when an option that was changed only takes effect after a restart of SQL Server.

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
        # Connect-DbaInstance tells us whether it opened a connection for us. We must only close what we opened
        # ourselves, because closing a connection of the caller takes their session with it. See #10554.
        $isNewSourceConnection = $false
        $isNewDestinationConnection = $false
        $isNewServerConnection = $false

        if (-not $PSBoundParameters.Path -and $PSBoundParameters.Source) {
            try {
                $splatConnectSource = @{
                    SqlInstance              = $Source
                    SqlCredential            = $SourceSqlCredential
                    IsNewConnectionReference = [ref]$isNewSourceConnection
                }
                $sourceserver = Connect-DbaInstance @splatConnectSource
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
                return
            }

            if (-not (Test-SqlSa -SqlInstance $sourceserver -SqlCredential $SourceSqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $sourceserver. Quitting." -Category PermissionDenied -Target $sourceserver -Continue
            }

            try {
                $splatConnectDestination = @{
                    SqlInstance              = $Destination
                    SqlCredential            = $DestinationSqlCredential
                    IsNewConnectionReference = [ref]$isNewDestinationConnection
                }
                $destserver = Connect-DbaInstance @splatConnectDestination
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination
                return
            }

            if (-not (Test-SqlSa -SqlInstance $destserver -SqlCredential $DestinationSqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $destserver. Quitting." -Category PermissionDenied -Target $destserver -Continue
            }

            $source = $sourceserver.DomainInstanceName
            $destination = $destserver.DomainInstanceName
        } else {
            try {
                $splatConnectServer = @{
                    SqlInstance              = $SqlInstance
                    SqlCredential            = $SqlCredential
                    IsNewConnectionReference = [ref]$isNewServerConnection
                }
                $server = Connect-DbaInstance @splatConnectServer
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
                # 'show advanced options' has to be on to read and to set the advanced options. It used to be
                # switched on and then off again, which turned it off on instances that had it on. Both instances
                # are now put back the way they were, in the finally block below, so that an option that cannot
                # be set does not leave them switched on either.
                $showAdvancedOptionsNumber = $sourceserver.Configuration.ShowAdvancedOptions.Number
                $sourceShowAdvancedOptions = $sourceserver.Configuration.ShowAdvancedOptions.ConfigValue
                $destShowAdvancedOptions = $destserver.Configuration.ShowAdvancedOptions.ConfigValue

                if ($sourceShowAdvancedOptions -eq 0) {
                    $sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
                    $sourceserver.Configuration.Alter($true)
                }
                if ($destShowAdvancedOptions -eq 0) {
                    # This used to alter the source a second time, so the option never reached the destination.
                    $destserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
                    $destserver.Configuration.Alter($true)
                }

                $needsrestart = $false
                $destprops = $destserver.Configuration.Properties

                try {
                    foreach ($sourceprop in $sourceserver.Configuration.Properties) {
                        $displayname = $sourceprop.DisplayName

                        # 'show advanced options' is the means to do the migration, not part of it.
                        if ($sourceprop.Number -eq $showAdvancedOptionsNumber) {
                            continue
                        }

                        $destprop = $destprops | Where-Object { $_.Displayname -eq $displayname }
                        if ($null -eq $destprop) {
                            continue
                        }

                        # Only options that really differ are touched. Assigning a value marks the property as
                        # changed even when it is the value that is already set, and Configuration.Alter() then
                        # sends every option of the instance in one batch, which fails as a whole as soon as one
                        # of them is not supported by the edition. That made the migration fail on SQL Server
                        # 2022 and newer even when both instances were already identical.
                        if ($destprop.ConfigValue -eq $sourceprop.ConfigValue) {
                            continue
                        }

                        try {
                            $destprop.configvalue = $sourceprop.configvalue
                            $destserver.Configuration.Alter($true)
                            if (-not $destprop.IsDynamic) {
                                $needsrestart = $true
                            }
                            Write-Message -Level Output -Message "updated $($destprop.displayname) to $($sourceprop.configvalue)."
                        } catch {
                            # An option that could not be set stays pending and would fail every following
                            # Alter() together with it, so the pending change is discarded before going on.
                            $destserver.Configuration.Refresh()
                            $destprops = $destserver.Configuration.Properties
                            Stop-Function -Message "Could not set $displayname to $($sourceprop.configvalue). Feature may not be supported." -ErrorRecord $_ -Continue
                        }
                    }
                } finally {
                    if ($destserver.Configuration.ShowAdvancedOptions.ConfigValue -ne $destShowAdvancedOptions) {
                        $destserver.Configuration.ShowAdvancedOptions.ConfigValue = $destShowAdvancedOptions
                        $destserver.Configuration.Alter($true)
                    }
                    if ($sourceserver.Configuration.ShowAdvancedOptions.ConfigValue -ne $sourceShowAdvancedOptions) {
                        $sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $sourceShowAdvancedOptions
                        $sourceserver.Configuration.Alter($true)
                    }
                }

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
                # 'show advanced options' is not touched here. It used to be set on the Configuration collection
                # without ever calling Alter(), so it never reached the instance - but it did leave a pending
                # change on the server object of the caller, which their next Alter() would have applied.
                # The file written by Export-DbaSpConfigure sets the option itself, first to 1 and then back to 0.
                $sql = Get-Content $Path
                foreach ($line in $sql) {
                    try {
                        $null = $server.Query($line)
                        Write-Message -Level Output -Message "Successfully executed $line."
                    } catch {
                        Stop-Function -Message "$line failed. Feature may not be supported." -ErrorRecord $_ -Continue
                    }
                }
                Write-Message -Level Warning -Message "Some configuration options will be updated once SQL Server is restarted."
            }
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }

        # Only close the connections that were opened here. See #10554.
        if ($isNewServerConnection) {
            $server.ConnectionContext.Disconnect()
        }
        if ($isNewSourceConnection) {
            $sourceserver.ConnectionContext.Disconnect()
        }
        if ($isNewDestinationConnection) {
            $destserver.ConnectionContext.Disconnect()
        }

        If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) {
            Write-Message -Level Output -Message "SQL Server configuration options migration finished."
        }
    }
}