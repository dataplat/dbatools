function Start-DbccCheck {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [object]$server,
        [string]$DbName,
        [switch]$table,
        [int]$MaxDop
    )

    $servername = $server.name

    if ($Pscmdlet.ShouldProcess($sourceserver, "Running dbcc check on $DbName on $servername")) {
        if ($server.ConnectionContext.StatementTimeout = 0 -ne 0) {
            $server.ConnectionContext.StatementTimeout = 0
        }

        try {
            if ($table) {
                $null = $server.databases[$DbName].CheckTables('None')
                Write-Verbose "Dbcc CheckTables finished successfully for $DbName on $servername"
            } else {
                if ($MaxDop) {
                    $null = $server.Query("DBCC CHECKDB ([$DbName]) WITH MAXDOP = $MaxDop")
                    Write-Verbose "Dbcc CHECKDB finished successfully for $DbName on $servername"
                } else {
                    $null = $server.Query("DBCC CHECKDB ([$DbName])")
                    Write-Verbose "Dbcc CHECKDB finished successfully for $DbName on $servername"
                }
            }
            return "Success"
        } catch {
            $message = $_.Exception
            if ($null -ne $_.Exception.InnerException) { $message = $_.Exception.InnerException }

            # english cleanup only sorry
            try {
                $newmessage = ($message -split "at Microsoft.SqlServer.Management.Common.ConnectionManager.ExecuteTSql")[0]
                $newmessage = ($newmessage -split "Microsoft.SqlServer.Management.Common.ExecutionFailureException:")[1]
                $newmessage = ($newmessage -replace "An exception occurred while executing a Transact-SQL statement or batch. ---> System.Data.SqlClient.SqlException:").Trim()
                $message = $newmessage
            } catch {
                $null
            }
            return $message.Trim()
        }
    }
}