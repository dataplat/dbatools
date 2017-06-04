function Restore-DbaSystemDatabase {
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

.PARAMETER AcceptClusterRisk
This function has been tested and works on clustered instances, but there have been occasions where the cluster has decide to failover and disrupt the restore.
As we don't want to break anything, by default we won't proceed against a clustered instance, unless this switch is present
Recommendation is that you disable services using Cluster management tools and then restore. 

.PARAMETER WhatIf
Shows what would happen if the command were to run. No actions are actually performed.

.PARAMETER Confirm
Prompts you for confirmation before executing any changing operations within the command.

.PARAMETER Silent
Use this switch to disable any kind of verbose messages

.NOTES
Original Author: Stuart Moore (@napalmgram), stuart-moore.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE 
Restore-DbaSystemDatabase -SqlInstance server1\prod1 -BackupPath \\server2\backups\master\master_20170411.bak -master

This will restore the master database on the server1\prod1 instance from the master db backup in \\server2\backups\master\master_20170411.bak

.EXAMPLE
Restore-DbaSystemDatabase -SqlInstance server1\prod1 -BackupPath \\server2\backups\msdb\msdb_20170411.bak -msdb

This will restore the msdb database on the server1\prod1 instance from the msdb db backup in \\server2\backups\master\master_20170411.bak

.EXAMPLE
Restore-DbaSystemDatabase -SqlInstance server1\prod1 -BackupPath \\server2\backups\master\,\\server2\backups\model\,\\server2\backups\msdb\  -msdb -model -master

This will restore the master, model and msdb on server1\prod1 to the most recent points in the backups in \\server2\backups\master\,\\server2\backups\model\,\\server2\backups\msdb\ respectively

.EXAMPLE
Restore-DbaSystemDatabase -SqlInstance server1\prod1 -BackupPath \\server2\backups\master\,\\server2\backups\model\,\\server2\backups\msdb\  -msdb -model -master -RestoreTime (Get-Date).AddHours(-2)

This will restore the master, model and msdb on server1\prod1 to a point in time 2 hours ago from the backups in \\server2\backups\master\,\\server2\backups\model\,\\server2\backups\msdb\ respectively

#>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param ([parameter(ValueFromPipeline, Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$Credential,
        [PSCredential]$SqlCredential,
        [String[]]$BackupPath,
        [DateTime]$RestoreTime = (Get-Date).addyears(1),
        [switch]$Master,
        [Switch]$Model,
        [Switch]$Msdb,
        [Switch]$Silent,
        [switch]$AcceptClusterRisk
    )
    begin {
        #workarounds requested by Klaas until Fred finished his work:
        Function Stop-DbaService {
            [CmdletBinding(SupportsShouldProcess = $true)]
            param (
                [Alias("ServerInstance", "SqlServer")]
                [DbaInstanceParameter[]]$SqlInstance,
                [PSCredential]$Credential,
                [ValidateSet('SqlServer', 'SqlAgent', 'FullText')]
                [String]$Service = 'SqlServer'
            )
			
			$ServerName = $SqlInstance.ComputerName
			$InstanceName = $SqlInstance.InstanceName
			
            if ($InstanceName.Length -eq 0) { $InstanceName = "MSSqlServer" }

           Write-Message -Level verbose "Attempting to stop SQL Service $InstanceName on $ServerName" 

            If ($Service -eq 'SqlServer') {
                $DisplayName = "SQL Server ($InstanceName)"  
            }

            If ($Service -eq 'SqlAgent') {
                $DisplayName = "Sql Server Agent ($InstanceName)"
            }

            if ($Service -eq 'FullText') {
                $DisplayName = "*Full*Text*($InstanceName)"        
            }

            $Scriptblock = {
                $ServerName = $args[0]
                $DisplayName = $args[1]
                    
                $wmisvc = $wmi.Services | Where-Object { $_.DisplayName -like $DisplayName }
               Write-Message -Level verbose "Attempting to Stop $DisplayName on $ServerName"
                try {
                    $timeout = new-timespan -Minutes 1
                    $timer = [diagnostics.stopwatch]::StartNew()
                    $wmisvc.stop()
                    while ($wmisvc.ServiceState -ne "Stopped" -and $timer.elapsed -lt $timeout) {  
                        $wmisvc.Refresh()  
                    }
                    if ($sw.elapsed -lt $timeout) {
                        [PSCustomObject]@{
                            Stopped = $true
                            Message = "Stopped $DisplayName on $ServerName successfully"
                        }           
                    }
                    else {
                        [PSCustomObject]@{
                            Stoped  = $False
                            Message = "$DisplayName on $ServerName failed to stop in a timely manner"
                        }     
                    }
                }
                catch {
                    [PSCustomObject]@{
                        Stopped = $false
                        Message = $_.Exception.Message
                    }
                }
            }
            if ($pscmdlet.ShouldProcess("Stopping $DisplayName on $ServerName")) {
                Invoke-ManagedComputerCommand -ComputerName $ServerName -Credential $credential -ScriptBlock $Scriptblock -ArgumentList $ServerName, $DisplayName
            }
        }

        Function Start-DbaService {
            param (
                [Alias("ServerInstance", "SqlServer")]
                [DbaInstanceParameter[]]$SqlInstance,
                [PSCredential]$Credential,
                [ValidateSet('SqlServer', 'SqlAgent', 'FullText')]
                [String]$Service = 'SqlServer'
			)
			
			$ServerName = $SqlInstance.ComputerName
			$InstanceName = $SqlInstance.InstanceName
			
			if ($InstanceName.Length -eq 0) { $InstanceName = "MSSqlServer" }
			
			if ($InstanceName.Length -eq 0) { $InstanceName = "MSSqlServer" }

           Write-Message -Level verbose "Attempting to Start SQL Service $InstanceName on $ServerName" 

            If ($Service -eq 'SqlServer') {
                $DisplayName = "SQL Server ($InstanceName)"  
            }

            If ($Service -eq 'SqlAgent') {
                $DisplayName = "Sql Server Agent ($InstanceName)"
            }

            if ($Service -eq 'FullText') {
                $DisplayName = "*Full*Text*($InstanceName)"        
            }

            $Scriptblock = {
                $ServerName = $args[0]
                $DisplayName = $args[1]
                    
                $wmisvc = $wmi.Services | Where-Object { $_.DisplayName -like $DisplayName }
                Write-Message -Level verbose "Attempting to Start $DisplayName on $ServerName"
                try {
                    $timeout = new-timespan -Minutes 1
                    $timer = [diagnostics.stopwatch]::StartNew()
                    $wmisvc.start()
                    while ($wmisvc.ServiceState -ne "Running" -and $timer.elapsed -lt $timeout) {  
                        $wmisvc.Refresh()  
                    }
                    if ($sw.elapsed -lt $timeout) {
                        [PSCustomObject]@{
                            Started = $true
                            Message = "Started $DisplayName on $ServerName successfully"
                        }           
                    }
                    else {
                        [PSCustomObject]@{
                            Started = $False
                            Message = "$DisplayName on $ServerName failed to start in a timely manner"
                        }     
                    }
                }
                catch {
                    [PSCustomObject]@{
                        Started = $false
                        Message = $_.Exception.Message
                    }
                }
            }
            if ($pscmdlet.ShouldProcess("Starting $DisplayName on $ServerName")) {
                Invoke-ManagedComputerCommand -ComputerName $ServerName -Credential $credential -ScriptBlock $Scriptblock -ArgumentList $ServerName, $DisplayName
            }
        }
    }


    process {
        $FunctionName = (Get-PSCallstack)[0].Command
        $RestoreResult = @()
		$ServerName = $SqlInstance.ComputerName
		$InstanceName = $SqlInstance.InstanceName
		
		if ($InstanceName.Length -eq 0) { $InstanceName = "MSSQLSERVER" }
		
        if (($PsBoundParameters.Keys | Where-Object {$_ -in ('master', 'msdb', 'model')} | measure-object).count -eq 0) {
            Stop-Function -Message "Must provide at least one of master, msdb or model switches" 
        }
        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -ApplicationName dbatoolsSystemk34i23hs3u57w
        }
        catch {
            Stop-Function -message "Cannot connect to $SqlInstance, stopping" -target $SqlInstance 
            return
        }
        if (($server.IsCluster) -and $AcceptClusterRisk -ne $true) {
            Stop-Function -message "Clustered Instance and AcceptClusterRisk not set, `n please read notes in help and decide how to proceed"
            return
        }
        $CurrentStartup = Get-DbaStartupParameter -SqlInstance $SqlInstance
        if ((Get-DbaSqlService -ComputerName $ServerName -Credential $Credential -Type Agent | Where-Object {$_.DisplayName -like "*$InstanceName*"}).State -eq 'Running') {
            Write-Message -Level Verbose -Message "SQL agent running, stopping it" 
            $RestartAgent = $True
            Stop-DbaService -SqlInstance $server -service SqlAgent | out-null
        }
        if ((Get-DbaSqlService -ComputerName $ServerName -Credential $Credential -Type FullText | Where-Object {$_.DisplayName -like "*$InstanceName*"}).State -eq 'Running') {
            Write-Message -Level Verbose -Message "Full Text agent running, stopping it" 
            $RestartFullText = $True
            Stop-DbaService -SqlInstance $server -service FullText | out-null
        }
        try {
            if ($true -eq $master) {
            
                Write-Message -Level Verbose -Message "Restoring Master, setting single user"
                Set-DbaStartupParameter -SqlInstance $server -SingleUser -SingleUserDetails dbatoolsSystemk34i23hs3u57w | out-null
                Stop-DbaService -SqlInstance $server | out-null
                Start-DbaService -SqlInstance $server | out-null
                $StartCount = 0
                while ((Get-DbaSqlService -ComputerName $ServerName -Credential $Credential -Type Engine | Where-Object {$_.DisplayName -like "*$InstanceName*"}).State -ne 'running') {
                    Start-DbaService -SqlInstance $server | out-null
                    Start-Sleep -seconds 65
                    $StartCount++
                    if ($StartCount -ge 4) {
                        #Didn't start nicely, jump to finally to try to come back up sanely
                        Stop-Function -Message "SQL Server not starting nicely, tried to fix, but not responding" 
                        return
                    }
                }
                if ($server.connectionContext.IsOpen -eq $false) {
                    $server.connectionContext.Connect()
                }
                Write-Message -Level Verbose  -Message  "Beginning Restore of Master"
                if ($pscmdlet.ShouldProcess("Restoring Master on $ServerName")) {
                    $RestoreResult += Restore-DbaDatabase -SqlInstance $server -Path $BackupPath -WithReplace -DatabaseFilter master -RestoreTime $RestoreTime -ReuseSourceFolderStructure -SystemRestore           
                }

                if ($RestoreResult.RestoreComplete -eq $True) {
                    Write-Message -Level Verbose  -Message "Restore of Master suceeded"   
                }
                else {
                    Write-Message -Level Warning  -Message "Restore of Master failed"   
                }
            }
            if (($true -eq $model) -or ($true -eq $msdb)) {
                Set-DbaStartupParameter -SqlInstance $server -SingleUser:$false  | out-null
                $filter = @()
                if ($true -eq $model) {
                    Write-Message -Level Verbose  -Message "Restoring Model, setting filter"
                    $filter += 'model'
                }
                if ($true -eq $msdb) {
                    Write-Message -Level Verbose  -Message "Restoring msdb, setting Filter"
                    $filter += 'msdb'
                }
                if ((Get-DbaSqlService -ComputerName $ServerName -Credential $Credential -Type Engine | Where-Object {$_.DisplayName -like "*$InstanceName*"}).State -eq 'Running') {
                    Stop-DbaService -SqlInstance $server | out-null
                }
                Start-DbaService -SqlInstance $server | out-null
                $StartCount = 0
                while ((Get-DbaSqlService -ComputerName $ServerName -Credential $Credential -Type Engine | Where-Object {$_.DisplayName -like "*$InstanceName*"}).State -ne 'running') {
                    Start-DbaService -SqlInstance $server | out-null
                    Start-Sleep -seconds 65
                    $StartCount++
                    if ($StartCount -ge 4) {
                        #Didn't start nicely, jump to finally to try to come back up sanely
                        Write-Message -Level Warning -Message "SQL Server not starting nicely, trying to fix" 
                    }
                }

                if ($server.connectionContext.IsOpen -eq $false) {
                    $server.connectionContext.Connect()
                }
                Write-Message -Level SomewhatVerbose  -Message "Starting restore of $($filter -join ',')"
                if ($pscmdlet.ShouldProcess("Restoring $($filter -join ',') on $ServerName")) {
                    $RestoreResults = Restore-DbaDatabase -SqlInstance $server -Path $BackupPath  -WithReplace -DatabaseFilter $filter -RestoreTime $RestoreTime -ReuseSourceFolderStructure -SystemRestore
                }
                Foreach ($Database in $RestoreResults) {
                    If ($Database.RestoreComplete) {
                        Write-Message -Level Verbose  -Message "Database $($Database.Databasename) restore suceeded"
                    }
                    else {
                        Write-Message -Level Warning  -Message "Database $($Database.Databasename) restore failed"
                    }
                }
            }
        }
        catch {
            Write-Message -Level Warning  -Message "An error has occured: $($error[0].Exception.Message)"
        }
        finally {
            if ((Get-DbaSqlService -ComputerName $ServerName -Credential $Credential -Type Engine | Where-Object {$_.DisplayName -like "*$InstanceName*"}).State -ne 'Running') {
                Start-DbaService -SqlInstance $server -service SqlServer | out-null
            }
            Write-Message -Level Verbose  -Message "Resetting Startup Parameters"
            Set-DbaStartupParameter -SqlInstance $server -StartUpConfig $CurrentStartup  | out-null
            Stop-DbaService -SqlInstance $server -Service SqlServer | out-null
            Start-DbaService -SqlInstance $server -service SqlServer | out-null
            if ($RestartAgent -eq $True) {
                Write-Message -Level Verbose  -Message "SQL Agent was running at start, so restarting"
                Start-DbaService -SqlInstance $server -service SqlAgent | out-null
            }
            if ($RestartFullText -eq $True) {
                Write-Message -Level Verbose  -Message "Full Text was running at start, so restarting"
                Start-DbaService -SqlInstance $server -service FullText | out-null
            }
            $Server.ConnectionContext.Disconnect()
            $RestoreResult + $RestoreResults
        }
    }
}