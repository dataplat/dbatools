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
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Destination
            Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

        .PARAMETER DestinationSqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Classic
            Perform the migration the old way
    
        .PARAMETER Force
            Drop destination objects first. Has no effect if you use Classic. This doesn't work really well, honestly.

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
            License: MIT https://opensource.org/licenses/MIT

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
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [switch]$Force,
        [switch]$Classic,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        function get-sqltypename ($type) {
            switch ($type) {
                "VIEW" { "View" }
                "SQL_TABLE_VALUED_FUNCTION" { "user table valued fsunction" }
                "DEFAULT_CONSTRAINT" { "user default constraint" }
                "SQL_STORED_PROCEDURE" { "user stored procedure" }
                "RULE" { "user rule" }
                "SQL_INLINE_TABLE_VALUED_FUNCTION" { "user inline table valued function" }
                "SQL_TRIGGER" { "user server trigger" }
                "SQL_SCALAR_FUNCTION" { "user scalar function" }
                default { $type }
            }
        }
    }
    process {
        try {
            Write-Message -Level Verbose -Message "Connecting to $Source"
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        }
        catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        
        if (!(Test-SqlSa -SqlInstance $sourceServer -SqlCredential $SourceSqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $source. Quitting."
            return
        }
        
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $destinstance"
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }
            
            if (!(Test-SqlSa -SqlInstance $destServer -SqlCredential $DestinationSqlCredential)) {
                Stop-Function -Message "Not a sysadmin on $destinstance" -Continue
            }
            
            $systemDbs = "master", "model", "msdb"
            
            if (-not $Classic) {
                foreach ($systemDb in $systemDbs) {
                    $smodb = $sourceServer.databases[$systemDb]
                    $tables = $smodb.Tables | Where-Object IsSystemObject -ne $true
                    
                    foreach ($table in $tables) {
                        $copyobject = [pscustomobject]@{
                            SourceServer = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Name         = $table.Name
                            Type         = "Table in $systemDb"
                            Status       = $null
                            Notes        = $null
                            DateTime     = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                        }
                        
                        $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $smodb
                        $null = $transfer.CopyAllObjects = $false
                        $null = $transfer.Options.WithDependencies = $true
                        $null = $transfer.ObjectList.Add($table)
                        if ($Force) {
                            $null = $transfer.DropDestinationObjectsFirst = $true
                        }
                        $sql = $transfer.ScriptTransfer()
                        if ($PSCmdlet.ShouldProcess($destServer, "Attempting to add table $($table.Name) to $systemDb")) {
                            try {
                                Write-Message -Level Debug -Message "$sql"
                                $null = $destServer.Query($sql, $systemDb)
                                $copyobject.Status = "Success"
                                $copyobject.Notes = "May have also created dependencies"
                            }
                            catch {
                                $copyobject.Status = "Failed"
                                $copyobject.Notes = $_.Exception.InnerException.InnerException.InnerException.InnerException.Message
                            }
                            $copyobject | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                    }
                    
                    $userobjects = Get-DbaSqlModule -SqlInstance $destServer -Database $systemDb -NoSystemObjects | Sort-Object Type
                    Write-Message -Level Verbose -Message "Copying from $systemDb."
                    foreach ($userobject in $userobjects) {
                        
                        $name = $userobject.Name
                        $db = $userobject.Database
                        $type = get-sqltypename $userobject.Type
                        $sql = $userobject.Definition
                        $schema = $userobject.SchemaName
                        
                        $copyobject = [pscustomobject]@{
                            SourceServer = $sourceServer.Name
                            DestinationServer = $destServer.Name
                            Name         = $name
                            Type         = "$type in $systemDb"
                            Status       = $null
                            Notes        = $null
                            DateTime     = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                        }
                        Write-Message -Level Debug -Message $sql
                        if ($PSCmdlet.ShouldProcess($destServer, "Attempting to add $type $name to $systemDb")) {
                            try {
                                $null = $destServer.Query($sql, $systemDb)
                                $copyobject.Status = "Successful"
                            }
                            catch {
                                $msg = $_.Exception.InnerException.InnerException.InnerException.InnerException.Message
                                if ($msg -match "already an object") {
                                    $copyobject.Status = "Failed"
                                    $copyobject.Notes = $_.Exception.InnerException.InnerException.InnerException.InnerException.Message
                                }
                                else {
                                    try {
                                        $smobject = switch ($userobject.Type) {
                                            "VIEW" { $smodb.Views.Item($name, $schema) }
                                            "SQL_TABLE_VALUED_FUNCTION" { $smodb.UserDefinedFunctions.Item($name, $schema) }
                                            "SQL_STORED_PROCEDURE" { $smodb.StoredProcedures.Item($name, $schema) }
                                            "RULE" { $smodb.Rules.Item($name, $schema) }
                                            "SQL_INLINE_TABLE_VALUED_FUNCTION" { $smodb.UserDefinedFunctions.Item($name, $schema) }
                                            "SQL_TRIGGER" { $smodb.Triggers.Item($name, $schema) }
                                            "SQL_SCALAR_FUNCTION" { $smodb.UserDefinedFunctions.Item($name, $schema) }
                                        }
                                        
                                        if ($smobject) {
                                            $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $smodb
                                            $null = $transfer.CopyAllObjects = $false
                                            $null = $transfer.Options.WithDependencies = $true
                                            $null = $transfer.ObjectList.Add($smobject)
                                            if ($Force) {
                                                $null = $transfer.DropDestinationObjectsFirst = $true
                                            }
                                            $sql = $transfer.ScriptTransfer()
                                            Write-Message -Level Debug -Message "$sql"
                                            $null = $smodb.Query($sql)
                                            $copyobject.Status = "Success"
                                            $copyobject.Notes = "May have also installed dependencies"
                                        }
                                        else {
                                            $copyobject.Status = "Failed"
                                            $copyobject.Notes = $msg
                                        }
                                    }
                                    catch {
                                        $copyobject.Status = "Failed"
                                        $copyobject.Notes = $msg
                                    }
                                }
                            }
                            $copyobject | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        }
                    }
                }
            }
            else {
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
                            Write-Message -Level Debug -Message "$sql"
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
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Copy-SqlSysDbUserObjects
    }
}