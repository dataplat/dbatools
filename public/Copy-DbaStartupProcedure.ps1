function Copy-DbaStartupProcedure {
    <#
    .SYNOPSIS
        Copies startup procedures from master database between SQL Server instances

    .DESCRIPTION
        Migrates user-defined startup procedures stored in the master database from source to destination SQL Server instances. Startup procedures are stored procedures that automatically execute when SQL Server starts up, commonly used for server initialization tasks, custom monitoring setup, or configuration validation.

        This function identifies procedures flagged with the startup option using sp_procoption, copies their definitions to the destination master database, and configures them as startup procedures. This is essential during server migrations, disaster recovery setup, or when standardizing startup configurations across multiple SQL Server environments.

        By default, all startup procedures are copied. Use -Procedure to copy specific procedures or -ExcludeProcedure to skip certain ones. Existing procedures on the destination are skipped unless -Force is used to overwrite them.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Procedure
        The startup procedure(s) to process. This list is auto-populated from the server. If unspecified, all startup procedures will be processed.

    .PARAMETER ExcludeProcedure
        The startup procedure(s) to exclude. This list is auto-populated from the server.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        If this switch is enabled, the custom error will be dropped and recreated if it already exists on Destination.

    .NOTES
        Tags: Migration, Procedure, Startup, StartupProcedure
        Author: Shawn Melton (@wsmelton), wsmelton.github.io

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Copy-DbaStartupProcedure

    .EXAMPLE
        PS C:\> Copy-DbaStartupProcedure -Source sqlserver2014a -Destination sqlcluster

        Copies all startup procedures from sqlserver2014a to sqlcluster using Windows credentials. If procedure(s) with the same name exists in the master database on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaStartupProcedure -Source sqlserver2014a -SourceSqlCredential $scred -Destination sqlcluster -DestinationSqlCredential $dcred -Procedure logstartup -Force

        Copies only the startup procedure, logstartup, from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If the procedure already exists on sqlcluster, it will be updated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaStartupProcedure -Source sqlserver2014a -Destination sqlcluster -ExcludeProcedure logstartup -Force

        Copies all the startup procedures found on sqlserver2014a except logstartup to sqlcluster. If a startup procedure with the same name exists on sqlcluster, it will be updated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaStartupProcedure -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string[]]$Procedure,
        [string[]]$ExcludeProcedure,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        # Includes properties: Name, Schema (both as strings)
        $startupProcs = Get-DbaModule -SqlInstance $sourceServer -Type StoredProcedure -Database master | Where-Object ExecIsStartup

        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destInstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            $destStartupProcs = Get-DbaModule -SqlInstance $destServer -Type StoredProcedure -Database master

            foreach ($currentProc in $startupProcs) {
                $currentProcName = $currentProc.Name
                $currentProcSchema = $currentProc.SchemaName
                $currentProcFullName = "$currentProcSchema.$currentProcName"

                $copyStartupProcStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $currentProcName
                    Schema            = $currentProcSchema
                    Status            = $null
                    Notes             = $null
                    Type              = "Startup Stored Procedure"
                    DateTime          = [DbaDateTime](Get-Date)
                }

                if ($Procedure -and ($Procedure -notcontains $currentProcName)) {
                    continue
                }

                if ($ExcludeProcedure -and ($ExcludeProcedure -contains $currentProcName)) {
                    continue
                }

                if ($destStartupProcs.Name -contains $currentProcName) {
                    if ($force -eq $false) {
                        if ($Pscmdlet.ShouldProcess($destInstance, "Startup procedure $currentProcFullName exists at destination. Use -Force to drop and migrate.")) {
                            $copyStartupProcStatus.Status = "Skipped"
                            $copyStartupProcStatus.Notes = "Already exists on destination"
                            $copyStartupProcStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "Startup procedure $currentProcFullName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destInstance, "Dropping startup procedure $currentProcFullName and recreating")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping startup procedure $currentProcFullName"
                                $destServer.Query("DROP PROCEDURE [$($currentProcSchema)].[$($currentProcName)]")
                            } catch {
                                $copyStartupProcStatus.Status = "Failed"
                                $copyStartupProcStatus.Notes = (Get-ErrorMessage -Record $_)
                                $copyStartupProcStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Issue dropping startup procedure $currentProcFullName on $destinstance | $PSItem"
                                continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destInstance, "Creating startup procedure $currentProcFullName")) {
                    try {
                        Write-Message -Level Verbose -Message "Copying startup procedure $currentProcFullName"
                        $sp = $sourceServer.Databases['master'].StoredProcedures.Item($currentProcName, $currentProcSchema)
                        $header = $sp.TextHeader
                        $body = $sp.TextBody
                        $sql = $header + $body
                        Write-Message -Level Verbose -Message $sql
                        $null = Invoke-DbaQuery -SqlInstance $destServer -Query $sql -Database master -EnableException
                        $startupSql = "EXEC SP_PROCOPTION '$currentProcName', 'STARTUP', 'ON'"
                        Write-Message -Level Verbose -Message $startupSql
                        $null = Invoke-DbaQuery -SqlInstance $destServer -Query $startupSql -Database master -EnableException

                        $copyStartupProcStatus.Status = "Successful"
                        $copyStartupProcStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copyStartupProcStatus.Status = "Failed"
                        $copyStartupProcStatus.Notes = (Get-ErrorMessage -Record $_)
                        $copyStartupProcStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating startup procedure $currentProcFullName on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}