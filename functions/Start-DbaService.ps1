function Start-DbaService
{
<#
.SYNOPSIS
Starts a SQL Server service on the speficied instace

.DESCRIPTION
Uses WMI services to start the requests SQL Server service on a instance

.PARAMETER SqlInstance
The SQL Server instance owning the service we want to start

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
Start-DbaService -SqlInstance server1\instance -Server SqlServer

This will attempt to start the SQL Server service underpinning server1\instance
	
.EXAMPLE
Start-DbaService -SqlInstance server1\instance -Server SqlAgent

This will attempt to start the SQL Server Agent service associated with server1\instance

.EXAMPLE
Start-DbaService -SqlInstance server1 -Server SqlServer

This will attempt to start the SQL Server service associated with the default instance on Server1

#>
    [CmdletBinding(SupportsShouldProcess=$true)]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
        [Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[PSCredential]$Credential,
        [ValidateSet('SqlServer','SqlAgent','FullText')]
        [String]$Service='SqlServer'
    )
    $FunctionName =(Get-PSCallstack)[0].Command

    #$ServerName, $InstanceName = ($sqlserver.Split('\'))
    if ($null -eq $SqlServer.name)
    {
        $ServerName, $InstanceName = ($sqlserver.Split('\'))
    }
    else
    {
        $ServerName, $InstanceName = ($sqlserver.name.Split('\'))
    }
   
    
    Write-Verbose "$FunctionName - Attempting to connect to $ServerName"
    
    if ($InstanceName.Length -eq 0) { $InstanceName = "MSSQLSERVER" }
    
    If ($Service -eq 'SqlServer')
    {
        $DisplayName = "SQL Server ($InstanceName)"  
    }

    If ($Service -eq 'SqlAgent')
    {
        $DisplayName ="Sql Server Agent ($InstanceName)"
    }

    if($Service -eq 'FullText')
    {
        $DisplayName = "*Full*Text*($InstanceName)"        
    }
    
    $Scriptblock = {
        $ServerName = $args[0]
        $DisplayName = $args[1]
            
        $wmisvc = $wmi.Services | Where-Object { $_.DisplayName -like $DisplayName }
        Write-Verbose "$FunctionName - Attempting to Start $DisplayName on $ServerName"
        try{
            $wmisvc.Start()
            $timeout = new-timespan -Minutes 1
            $timer = [diagnostics.stopwatch]::StartNew()
            while ($wmisvc.ServiceState -ne "Running" -and $timer.elapsed -lt $timeout)  
            {  
                $wmisvc.Refresh() 
            } 
            if ($sw.elapsed -lt $timeout){
                [PSCustomObject]@{
                    Started = $true
                    Message = "Started $DisplayName on $ServerName successfully"
                    } 
            }
            else 
            {
                [PSCustomObject]@{
                    Started = $False
                    Message = "$DisplayName on $ServerName failed to start in a timely manner"
                    }
            }

        }
        catch
        {
            [PSCustomObject]@{
                    Started = $false
                    Message = $_.Exception.Message
                }
        }
    }
    if ($pscmdlet.ShouldProcess("Starting $Service on $SqlServer ")) {
        Invoke-ManagedComputerCommand -ComputerName $ServerName -Credential $credential -ScriptBlock $Scriptblock -ArgumentList $ServerName, $DisplayName
    }
}