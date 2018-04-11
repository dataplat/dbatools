function Import-DbaSpConfigure {
    <#
        .SYNOPSIS
            Updates sp_configure settings on destination server.

        .DESCRIPTION
            Updates sp_configure settings on destination server.

        .PARAMETER Source
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SourceSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

        .PARAMETER DestinationSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER SqlInstance
            Specifies a SQL Server instance to set up sp_configure values on using a SQL file.

        .PARAMETER SqlCredential
            Use this SQL credential if you are setting up sp_configure values from a SQL file.

            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Path
            Specifies the path to a SQL script file holding sp_configure queries for each of the settings to be changed. Export-DbaSPConfigure creates a suitable file as its output.

        .PARAMETER Force
            If this switch is enabled, no version check between Source and Destination is performed. By default, the major and minor versions of Source and Destination must match when copying sp_configure settings.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .NOTES
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .EXAMPLE
            Import-DbaSpConfigure sqlserver sqlcluster $SourceSqlCredential $DestinationSqlCredential

            Imports the sp_configure settings from the source server sqlserver and sets them on the sqlcluster server
            using the SQL credentials stored in the variables

        .EXAMPLE
            Import-DbaSpConfigure -SqlInstance sqlserver -Path .\spconfig.sql -SqlCredential $SqlCredential

            Imports the sp_configure settings from the file .\spconfig.sql and sets them on the sqlcluster server
            using the SQL credential stored in the variables

        .OUTPUTS
            $true if success
            $false if failure

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
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
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [Parameter(ParameterSetName = "FromFile")]
        [string]$Path,
        [Parameter(ParameterSetName = "FromFile")]
        [PSCredential]$SqlCredential,
        [switch]$Force

    )
    begin {

        if ($Path.length -eq 0) {
            $sourceserver = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
            $destserver = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

            $source = $sourceserver.DomainInstanceName
            $destination = $destserver.DomainInstanceName
        }
        else {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
            if ((Test-Path $Path) -eq $false) {
                throw "File Not Found"
            }
        }

    }
    process {
        if ($Path.length -eq 0) {
            if ($Pscmdlet.ShouldProcess($destination, "Export sp_configure")) {
                $sqlfilename = Export-SqlSpConfigure $sourceserver
            }

            if ($sourceserver.versionMajor -ne $destserver.versionMajor -and $force -eq $false) {
                Write-Warning "Source SQL Server major version and Destination SQL Server major version must match for sp_configure migration. Use -Force to override this precaution or check the exported sql file, $sqlfilename, and run manually."
                return
            }

            If ($Pscmdlet.ShouldProcess($destination, "Execute sp_configure")) {
                $sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
                $sourceserver.Query("RECONFIGURE WITH OVERRIDE") | Out-Null
                $destserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
                $destserver.Query("RECONFIGURE WITH OVERRIDE") | Out-Null

                $destprops = $destserver.Configuration.Properties

                foreach ($sourceprop in $sourceserver.Configuration.Properties) {
                    $displayname = $sourceprop.DisplayName

                    $destprop = $destprops | where-object { $_.Displayname -eq $displayname }
                    if ($null -ne $destprop) {
                        try {
                            $destprop.configvalue = $sourceprop.configvalue
                            $destserver.Query("RECONFIGURE WITH OVERRIDE") | Out-Null
                            Write-Output "updated $($destprop.displayname) to $($sourceprop.configvalue)."
                        }
                        catch {
                            Write-Error "Could not $($destprop.displayname) to $($sourceprop.configvalue). Feature may not be supported."
                        }
                    }
                }
                try {
                    $destserver.Configuration.Alter()
                }
                catch {
                    $needsrestart = $true
                }

                $sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
                $sourceserver.Query("RECONFIGURE WITH OVERRIDE") | Out-Null
                $destserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
                $destserver.Query("RECONFIGURE WITH OVERRIDE") | Out-Null

                if ($needsrestart -eq $true) {
                    Write-Warning "Some configuration options will be updated once SQL Server is restarted."
                }
                else {
                    Write-Output "Configuration option has been updated."
                }
            }

            if ($Pscmdlet.ShouldProcess($destination, "Removing temp file")) {
                Remove-Item $sqlfilename -ErrorAction SilentlyContinue
            }

        }
        else {
            if ($Pscmdlet.ShouldProcess($destination, "Importing sp_configure from $Path")) {
                $server.Configuration.ShowAdvancedOptions.ConfigValue = $true
                $sql = Get-Content $Path
                foreach ($line in $sql) {
                    try {
                        $server.Query($line) | Out-Null
                        Write-Output "Successfully executed $line."
                    }
                    catch {
                        Write-Error "$line failed. Feature may not be supported."
                    }
                }
                $server.Configuration.ShowAdvancedOptions.ConfigValue = $false
                Write-Warning "Some configuration options will be updated once SQL Server is restarted."
            }
        }
    }
    end {
        if ($Path.length -gt 0) {
            $server.ConnectionContext.Disconnect()
        }
        else {
            $sourceserver.ConnectionContext.Disconnect()
            $destserver.ConnectionContext.Disconnect()
        }

        If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) {
            Write-Output "SQL Server configuration options migration finished."
        }

        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Import-SqlSpConfigure
    }
}