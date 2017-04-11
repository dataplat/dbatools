function Restore-DbaSystemDatabase
{
    <#
.SYNOPSIS
Restores the SQL Server system databases (master, mode, msdb)
.DESCRIPTION
Performs all the actions required for restoring SQL Server system databases

For master the SQL Server instance will be started in single user mode to allow the restore
For msdb or model, the SQL Agent service will be stopped to allow exclusive access and then restarted afterwards

Startup parameters will be modified, but an existing ones will be push back in after success (or failure)

.PARAMETER SqlInstance
The SQL Server instance targetted for restores

.PARAMETER SqlCredential
SQL Server credential (Windows or SQL Accounnt) with permission to log on to the SQL instance to perform the restores

.PARAMETER Credential
Windows credential with permission to log on to the server running the SQL instance (this is required for the stop/start action). If not present, the account running the function's credentials will be used

.PARAMETER BackupPath
Path to the backup files to be used for the restore. Multiple paths can be specified 

.PARAMETER RestoreTime
DateTime parameter to say to which point in time the system database(s) should be restored to

.PARAMETER master
Switch to indicate that the master database should be restored

.PARAMETER model
Switch to indicate that the model database should be restored

.PARAMETER msdb
Switch to indicate that the msdb database should be restored

.NOTES
Original Author: Stuart Moore (@napalmgram), stuart-moore.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE 
Restore-DbaSystemDatabase -SqlServer server1\prod1 -BackupPath \\server2\backups\master\master_20170411.bak -master

This will restore the master database on the server1\prod1 instance from the master db backup in \\server2\backups\master\master_20170411.bak

.EXAMPLE
Restore-DbaSystemDatabase -SqlServer server1\prod1 -BackupPath \\server2\backups\msdb\msdb_20170411.bak -msdb

This will restore the msdb database on the server1\prod1 instance from the msdb db backup in \\server2\backups\master\master_20170411.bak

.EXAMPLE
Restore-DbaSystemDatabase -SqlServer server1\prod1 -BackupPath \\server2\backups\master\,\\server2\backups\model\,\\server2\backups\msdb\  -msdb -model -master

This will restore the master, model and msdb on server1\prod1 to the most recent points in the backups in \\server2\backups\master\,\\server2\backups\model\,\\server2\backups\msdb\ respectively

.EXAMPLE
Restore-DbaSystemDatabase -SqlServer server1\prod1 -BackupPath \\server2\backups\master\,\\server2\backups\model\,\\server2\backups\msdb\  -msdb -model -master -RestoreTime (Get-Date).AddHours(-2)

This will restore the master, model and msdb on server1\prod1 to a point in time 2 hours ago from the backups in \\server2\backups\master\,\\server2\backups\model\,\\server2\backups\msdb\ respectively

#>
    [CmdletBinding(SupportsShouldProcess=$true)]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[PSCredential]$Credential,
        [PSCredential]$SqlCredential,
        [String[]]$BackupPath,
        [DateTime]$RestoreTime,
        [switch]$Master,
        [Switch]$Model,
        [Switch]$Msdb
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