function Copy-DbaSysDbUserObject {
    <#
        .SYNOPSIS
            Imports all user objects found in source SQL Server's master, msdb and model databases to the destination.

        .DESCRIPTION
            Imports all user objects found in source SQL Server's master, msdb and model databases to the destination. This is useful because many DBAs store backup/maintenance procs/tables/triggers/etc (among other things) in master or msdb.

            It is also useful for migrating objects within the model database.

        .PARAMETER Source
            Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

        .PARAMETER SourceSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter.

            Windows Authentication will be used if SourceSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

        .PARAMETER DestinationSqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter.

            Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Migration, SystemDatabase, UserObject

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Copy-DbaSysDbUserObject

        .EXAMPLE
            Copy-DbaSysDbUserObject $sourceServer $destserver

            Copies user objects from source to destination
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [DbaInstanceParameter]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [switch][Alias('Silent')]$EnableException
    )
    process {
        $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        $destServer = Connect-SqlInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential

        $source = $sourceServer.DomainInstanceName
        $destination = $destServer.DomainInstanceName

        if (!(Test-SqlSa -SqlInstance $sourceServer -SqlCredential $SourceSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $source. Quitting."
            return
        }
        if (!(Test-SqlSa -SqlInstance $destServer -SqlCredential $DestinationSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $destination. Quitting."
            return
        }

        $systemDbs = "master", "model", "msdb"

        foreach ($systemDb in $systemDbs) {
            $sysdb = $sourceServer.databases[$systemDb]
            $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $sysdb
            $transfer.CopyAllObjects = $false
            $transfer.CopyAllDatabaseTriggers = $true
            $transfer.CopyAllDefaults = $true
            $transfer.CopyAllRoles = $true
            $transfer.CopyAllRules = $true
            $transfer.CopyAllSchemas = $true
            $transfer.CopyAllSequences = $true
            $transfer.CopyAllSqlAssemblies = $true
            $transfer.CopyAllSynonyms = $true
            $transfer.CopyAllTables = $true
            $transfer.CopyAllViews = $true
            $transfer.CopyAllStoredProcedures = $true
            $transfer.CopyAllUserDefinedAggregates = $true
            $transfer.CopyAllUserDefinedDataTypes = $true
            $transfer.CopyAllUserDefinedTableTypes = $true
            $transfer.CopyAllUserDefinedTypes = $true
            $transfer.CopyAllUserDefinedFunctions = $true
            $transfer.CopyAllUsers = $true
            $transfer.PreserveDbo = $true
            $transfer.Options.AllowSystemObjects = $false
            $transfer.Options.ContinueScriptingOnError = $true
            $transfer.Options.IncludeDatabaseRoleMemberships = $true
            $transfer.Options.Indexes = $true
            $transfer.Options.Permissions = $true
            $transfer.Options.WithDependencies = $false

            Write-Message -Level Output -Message "Copying from $systemDb."
            try {
                $sqlQueries = $transfer.ScriptTransfer()

                foreach ($sql in $sqlQueries) {
                    Write-Message -Level Debug -Message $sql
                    if ($PSCmdlet.ShouldProcess($destServer, $sql)) {
                        try {
                            $destServer.Query($sql, $systemDb)
                        }
                        catch {
                            # Don't care - long story having to do with duplicate stuff
                        }
                    }
                }
            }
            catch {
                # Don't care - long story having to do with duplicate stuff
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlSysDbUserObjects
    }
}