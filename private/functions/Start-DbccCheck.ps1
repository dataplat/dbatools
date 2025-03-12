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
        if ($server.ConnectionContext.StatementTimeout -ne 0) {
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
            $originalException = $_.Exception
            $loopNo = 0
            while ($loopNo -ne 5)
            {
                $loopNo ++
                if ($null -ne $originalException.InnerException) { 
                    $originalException = $originalException.InnerException 
                } else {
                    break
                }
            }
            $message = $originalException.ToString()
            
            # english cleanup only sorry
            try {
                $newmessage = $message
                if ($newmessage -like '*at Microsoft.SqlServer.Management.Common.ConnectionManager.ExecuteTSql*')
                {
                    $newmessage = ($newmessage -split "at Microsoft.SqlServer.Management.Common.ConnectionManager.ExecuteTSql")[0]
                }
                if ($newmessage -like '*Microsoft.SqlServer.Management.Common.ExecutionFailureException:*')
                {
                    $newmessage = ($newmessage -split "Microsoft.SqlServer.Management.Common.ExecutionFailureException:")[1]
                }
                if ($newmessage -like '*An exception occurred while executing a Transact-SQL statement or batch. ---> Microsoft.Data.SqlClient.SqlException:*')
                {
                    $newmessage = ($newmessage -replace "An exception occurred while executing a Transact-SQL statement or batch. ---> Microsoft.Data.SqlClient.SqlException:").Trim()
                }
                if ($newmessage -like '*An exception occurred while executing a Transact-SQL statement or batch*')
                {
                    $newmessage = ($newmessage -split "An exception occurred while executing a Transact-SQL statement or batch")[1]
                }
                
                $message = $newmessage
            } catch {
                $null
            }
            return $message.Trim()
        }
    }
}