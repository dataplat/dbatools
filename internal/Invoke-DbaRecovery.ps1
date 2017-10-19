Function Invoke-DbaRecovery
{
<# 
	.SYNOPSIS
    Internal function. Performs recovery on a database in a recoverying state

#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [string[]]$DatabaseName
    [parameter(Mandatory = $true)]
    [Alias("ServerInstance", "SqlServer")]
    [DbaInstanceParameter]$SqlInstance,
    [PSCredential]$SqlCredential
}
Begin{}
Process{
    ForEach ($Database in $DatabaseName){
        try {
            $Server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Write-Message -Level Warning -Message "Cannot connect to $SqlInstance"
            break
        }

        $ServerName = $Server.name
        $Server.ConnectionContext.StatementTimeout = 0
        $Restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
        $Restore.Database = $Database
        $Restore.NoRecovery = $false
        Write-Message -Level Verbose -Message "Beginning Restore of $DbDatabase"
        $Restore.add_PercentComplete($percent)
        $Restore.PercentCompleteNotification = 1
        $Restore.add_Complete($complete)
        try {
            $RestoreComplete = $true
            if ($ScriptOnly) {
                $script = $Restore.Script($server)
            }
            Write-Progress -id 2 -activity "Recovering $Database to $ServerName" -percentcomplete 0 -status ([System.String]::Format("Progress: {0} %", 0))
            $script = $Restore.Script($Server)
            $Restore.sqlrestore($Server)
            Write-Progress -id 2 -activity "Restoring $Database to $ServerName" -status "Complete" -Completed
        
        }
        catch {
            $RestoreComplete = $False
            $ExitError = $_.Exception.InnerException
            Stop-Function -Message "Failed to recover db $Database, stopping" -ErrorRecord $_
            return
        }
    }
}