function Stop-DbaService
{
<#
.SYNOPSIS
Stops a SQL Server service on the speficied instace

.DESCRIPTION
Uses WMI services to stop the requests SQL Server service on a instance

.PARAMETER SqlInstance
The SQL Server instance owning the service we want to stop

.PARAMETER Credential
Windows credential with permission to log on to the server running the SQL instance

.PARAMETER Service
Which SQL Server service to start.
Valid values are SqlServer and SqlAgent

.NOTES
Original Author: Stuart Moore (@napalmgram), stuart-moore.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE 
Stop-DbaService -SqlInstance server1\instance -Server SqlServer

This will attempt to stop the SQL Server service underpinning server1\instance
	
.EXAMPLE
Stop-DbaService -SqlInstance server1\instance -Server SqlAgent

This will attempt to stop the SQL Server Agent service associated with server1\instance

.EXAMPLE
Stop-DbaService -SqlInstance server1 -Server SqlServer

This will attempt to stop the SQL Server service associated with the default instance on Server1

#>
    [CmdletBinding(SupportsShouldProcess=$true)]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
        [Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[PSCredential]$Credential,
        [ValidateSet('SqlServer','SqlAgent')]
        [String]$Service='SqlServer'
    )
    $FunctionName =(Get-PSCallstack)[0].Command

    $servername, $instancename = ($sqlserver.Split('\'))
    Write-Verbose "Attempting to connect to $servername"
    
    if ($instancename.Length -eq 0) { $instancename = "MSSQLSERVER" }
    
    If ($Service -eq 'SqlServer')
    {
        $displayname = "SQL Server ($instancename)"  
    }

    If ($Service -eq 'SqlAgent')
    {
        $displayname ="Sql Server Agent ($instancename)"
    }
    
    $Scriptblock = {
        $servername = $args[0]
        $displayname = $args[1]
            
        $wmisvc = $wmi.Services | Where-Object { $_.DisplayName -eq $displayname }
        Write-Verbose "Attempting to Stop $displayname on $servername"
        try{
            $timeout = new-timespan -Minutes 1
            $timer = [diagnostics.stopwatch]::StartNew()
            $wmisvc.stop()
            while ($wmisvc.ServiceState -ne "Stopped" -and $timer.elapsed -lt $timeout)  
            {  
                $wmisvc.Refresh()  
            }
            if ($sw.elapsed -ge $timeout){
                [PSCustomObject]@{
                    Started = $False
                    Message = "$displayname on $servername failed to stop in a timely manner"
                    }
            }
            else {
                [PSCustomObject]@{
                    Stopped = $true
                    Message = "Stopped $displayname on $servername successfully"
                    }                
            }
        }
        catch
        {
            [PSCustomObject]@{
                    Stopped = $false
                    Message = $_.Exception.Message
                }
        }
    }
 
    if ($pscmdlet.ShouldProcess("Stopping $Service on $SqlServer ")) {
        Invoke-ManagedComputerCommand -ComputerName $servername -Credential $credential -ScriptBlock $Scriptblock -ArgumentList $servername, $displayname
    }
}