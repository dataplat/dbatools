function Get-DbaService
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

.NOTES
Original Author: Stuart Moore (@napalmgram), stuart-moore.com

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.EXAMPLE 
Get-DbaService -SqlInstance server1\instance 

Will return the status of all SQL Server services running on  server1\instance

#>
    [CmdletBinding(SupportsShouldProcess=$true)]
	param ([parameter(ValueFromPipeline, Mandatory = $true)]
        [Alias("ServerInstance", "SqlInstance")]
		[object[]]$SqlServer,
		[PSCredential]$Credential,
        [ValidateSet('SqlServer','SqlAgent','All')]
        [String]$Service='All'
    )
    $FunctionName =(Get-PSCallstack)[0].Command

        #$servername, $instancename = ($sqlserver.Split('\'))
    if ($null -eq $SqlServer.name)
    {
        $servername, $instancename = ($sqlserver.Split('\'))
    }
    else
    {
        $servername, $instancename = ($sqlserver.name.Split('\'))
    }
   
    if ($instancename.Length -eq 0) { $instancename = "MSSQLSERVER" }
    Write-Verbose "Attempting to connect to $servername"
    
    if ($Service -eq 'SqlServer')
    {
        $instanceName = "Sql Server ($InstanceName)"
    }

    if ($Service -eq 'SqlAgent')
    {
        $instanceName = "Sql Server Agent ($InstanceName)"
    }

    $Scriptblock = {
        $servername = $args[0]
        $displayname = $args[1]
        
            
        $wmi.Services | Where-Object { $_.DisplayName -like "*$displayname*" } |  Select-Object Displayname, ServiceState
        
    }

    Invoke-ManagedComputerCommand -ComputerName $servername -Credential $credential -ScriptBlock $Scriptblock -ArgumentList $servername, $instancename
}