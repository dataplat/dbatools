function Get-DbaSysDbUserObjectScript {
    <#
        .SYNOPSIS
            Gets all user objects found in source SQL Server's master, msdb and model databases to the destination.
       #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$EnableException
    )
    begin {
        function get-sqltypename ($type) {
            switch ($type) {
                "VIEW" { "view" }
                "SQL_TABLE_VALUED_FUNCTION" { "User table valued fsunction" }
                "DEFAULT_CONSTRAINT" { "User default constraint" }
                "SQL_STORED_PROCEDURE" { "User stored procedure" }
                "RULE" { "User rule" }
                "SQL_INLINE_TABLE_VALUED_FUNCTION" { "User inline table valued function" }
                "SQL_TRIGGER" { "User server trigger" }
                "SQL_SCALAR_FUNCTION" { "User scalar function" }
                default { $type }
            }
        }
    }
    process {
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }

        if (!(Test-SqlSa -SqlInstance $server -SqlCredential $SqlCredential)) {
            Stop-Function -Message "Not a sysadmin on $source. Quitting."
            return
        }

        $systemDbs = "master", "model", "msdb"

        foreach ($systemDb in $systemDbs) {
            $smodb = $server.databases[$systemDb]
            $destdb = $server.databases[$systemDb]
            Write-Output "USE $systemDb"
            Write-Output "GO"
            $tables = $smodb.Tables | Where-Object IsSystemObject -ne $true
            $schemas = $smodb.Schemas | Where-Object IsSystemObject -ne $true
            $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $smodb
            $null = $transfer.CopyAllObjects = $false
            $null = $transfer.Options.WithDependencies = $true
            $null = $transfer.ObjectList.Add($schema)
            $null = $transfer.Options.ScriptBatchTerminator = $true
            try { $transfer.ScriptTransfer() }
            catch { }
            Write-Output "GO"

            foreach ($table in $tables) {
                Write-Output "GO"
                $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $smodb
                $null = $transfer.CopyAllObjects = $false
                $null = $transfer.Options.WithDependencies = $true
                $null = $transfer.Options.ScriptBatchTerminator = $true
                $null = $transfer.ObjectList.Add($table)
                try { $transfer.ScriptTransfer() } catch {}
            }

            $userobjects = Get-DbaModule -SqlInstance $server -Database $systemDb -ExcludeSystemObjects | Sort-Object Type
            Write-Message -Level Verbose -Message "Copying from $systemDb"
            foreach ($userobject in $userobjects) {
                Write-Output "GO"
                $name = "[$($userobject.SchemaName)].[$($userobject.Name)]"
                $db = $userobject.Database
                $type = get-sqltypename $userobject.Type
                $userobject.Definition
                $schema = $userobject.SchemaName
                $result = Get-DbaModule -SqlInstance $server -ExcludeSystemObjects -Database $db |
                    Where-Object { $psitem.Name -eq $userobject.Name -and $psitem.Type -eq $userobject.Type }
                $smobject = switch ($userobject.Type) {
                    "VIEW" { $smodb.Views.Item($userobject.Name, $userobject.SchemaName) }
                    "SQL_STORED_PROCEDURE" { $smodb.StoredProcedures.Item($userobject.Name, $userobject.SchemaName) }
                    "RULE" { $smodb.Rules.Item($userobject.Name, $userobject.SchemaName) }
                    "SQL_TRIGGER" { $smodb.Triggers.Item($userobject.Name, $userobject.SchemaName) }
                    "SQL_TABLE_VALUED_FUNCTION" { $smodb.UserDefinedFunctions.Item($name) }
                    "SQL_INLINE_TABLE_VALUED_FUNCTION" { $smodb.UserDefinedFunctions.Item($name) }
                    "SQL_SCALAR_FUNCTION" { $smodb.UserDefinedFunctions.Item($name) }
                }

                $smobject = switch ($userobject.Type) {
                    "VIEW" { $smodb.Views.Item($userobject.Name, $userobject.SchemaName) }
                    "SQL_STORED_PROCEDURE" { $smodb.StoredProcedures.Item($userobject.Name, $userobject.SchemaName) }
                    "RULE" { $smodb.Rules.Item($userobject.Name, $userobject.SchemaName) }
                    "SQL_TRIGGER" { $smodb.Triggers.Item($userobject.Name, $userobject.SchemaName) }
                }
                if ($smobject) {
                    $transfer = New-Object Microsoft.SqlServer.Management.Smo.Transfer $smodb
                    $null = $transfer.CopyAllObjects = $false
                    $null = $transfer.Options.WithDependencies = $true
                    $null = $transfer.ObjectList.Add($smobject)
                    $null = $transfer.Options.ScriptBatchTerminator = $true
                    try { $transfer.ScriptTransfer() } catch {}
                }
            }
        }
    }
}