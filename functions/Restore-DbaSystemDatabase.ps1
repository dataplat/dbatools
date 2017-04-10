function Restore-DbaSystemDatabase
{
    [CmdletBinding(SupportsShouldProcess=$true)]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[PSCredential]$Credential,
        [PSCredential]$SqlCredential,
        [String[]]$BackupPath,
        [DateTime]$RestorePoint,
        [switch]$master,
        [Switch]$model,
        [Switch]$msdb
	)

    $FunctionName =(Get-PSCallstack)[0].Command
    [bool]$silent = $true
    try
    {
        $server = connect-SqlServer -SqlServer $SqlServer -applicationName dbatoolsSystemk34i23hs3u57w
    }
    catch
    {
        Stop-Function -message "Cannot connect to $sqlserver, stopping" -target $SqlServer
    }
    $CurrentStartup = Get-DbaStartupParameter -SqlServer $server
    if ((Get-DbaService -sqlserver $server -service SqlAgent).ServiceState -eq 'Running')
    {
        Write-Verbose "$FunctionName - SQL agent running, stopping it"
        $RestartAgent = $True
        Stop-DbaService -sqlserver $server -service SqlAgent | out-null
    }
    try
    {
        if ($master)
        {
        
            Write-Verbose "$FunctionName - Restoring Master, setting single user"
            Set-DbaStartupParameter -SqlServer $sqlserver -SingleUser -SingleUserDetails dbatoolsSystemk34i23hs3u57w 
            Stop-DbaService -SqlServer $server | out-null
            Start-DbaService -SqlServer $server | out-null
            Write-Verbose "$FunctionName - Beginning Restore of Master"
            
            $MasterRestoreResult = Restore-DbaDatabase -SqlServer $server -Path $BackupPath -WithReplace -DatabaseFilter master
            if ($MasterRestoreResult.RestoreComplete -eq $True)
            {
                Write-Verbose "$FunctionName - Restore of Master suceeded"   
            }
            else
            {
                Write-Verbose "$FunctionName - Restore of Master failed"   
            }
            Write-Verbose "1 - $((Get-DbaService -sqlserver $server -service sqlserver).ServiceState)"
            
        }
        if ($model -or $msdb)
        {
            Set-DbaStartupParameter -SqlServer $sqlserver -SingleUser:$false | out-null
            Write-Verbose "$FunctionName - Model or msdb to restore"
            $filter = @()
            if ($model)
            {
                Write-Verbose "$FunctionName - Restoring Model, setting filter"
                $filter += 'model'
            }
            if ($msdb)
            {
                Write-Verbose "$FunctionName - Restoring msdb, setting Filter"
                $filter += 'msdb'
            }
            if ((Get-DbaService -sqlserver $server -service SqlServer).ServiceState -eq 'Running')
            {
                Stop-DbaService -SqlServer $server | out-null
            }
            Start-DbaService -SqlServer $server | out-null
            while ((Get-DbaService -sqlserver $server -service sqlserver).ServiceState -ne 'running')
            {
                Start-Sleep -seconds 15
            }
            Write-Verbose "$FunctionName - Starting restore of $($filter -join ',')"
            $RestoreResults = Restore-DbaDatabase -SqlServer $server -Path $BackupPath  -WithReplace -DatabaseFilter $filter -verbose
            Foreach ($Database in $RestoreResults)
            {
                If ($Database.RestoreComplete)
                {
                    Write-Verbose "$FunctionName - Database $($Database.Databasename) restore suceeded"
                }
                else
                {
                    Write-Verbose "$FunctionName - Database $($Database.Databasename) restore failed"
                }
            }
        }
    }
    catch
    {
        $error[0].Exception.Message
    }
    finally
    {
        Write-Verbose "$FunctionName - In the Finally block"
        if ((Get-DbaService -sqlserver $server -service SqlServer).ServiceState -ne 'Running')
        {
            Write-Verbose "$FunctionName - SQL Server not running, starting it up"
            Start-DbaService -sqlserver $server -service SqlServer | out-null
        }
        Write-Verbose "2 - $((Get-DbaService -sqlserver $server -service sqlserver).ServiceState)"
        Set-DbaStartupParameter -SqlServer $sqlserver -StartUpConfig $CurrentStartup 
        Stop-DbaService -SqlServer $server -Service SqlServer | out-null
        Write-Verbose "3 - $((Get-DbaService -sqlserver $server -service sqlserver).ServiceState)"
        Start-DbaService -SqlServer $server -service SqlServer | out-null
        Write-Verbose "4 - $((Get-DbaService -sqlserver $server -service sqlserver).ServiceState)"
        if ($RestartAgent -eq $True)
        {
            Write-Verbose "$Function - SQL Agent was running at start, so restarting"
            Start-DbaService -sqlserver $server -service SqlAgent | out-null
        }
        Write-Verbose "5 - $((Get-DbaService -sqlserver $server -service sqlserver).ServiceState)"
         [PSCustomObject]@{
                RestoreScripts = ($MasterRestoreResult ,$RestoreResults)   
                }

    }
}