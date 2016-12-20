Function Get-DbaSqlService
{
<#
.SYNOPSIS
Gets the SQL Server related services on a computer. 

.DESCRIPTION
Gets the SQL Server related services on one or more computers.

Requires Local Admin rights on destination computer(s).

.PARAMETER ComputerName
The SQL Server (or server in general) that you're connecting to. This command handles named instances.

.PARAMETER Credential
Credential object used to connect to the computer as a different user.

.NOTES
Author: Klaas Vandenberghe ( @PowerDBAKlaas )

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

.LINK
https://dbatools.io/Get-DbaSqlService

.EXAMPLE
Get-DbaSqlService -ComputerName sqlserver2014a

Gets the SQL Server related services on computer sqlserver2014a.

.EXAMPLE   
'sql1','sql2','sql3' | Get-DbaSqlService

Gets the SQL Server related services on computers sql1, sql2 and sql3.

.EXAMPLE
Get-DbaSqlService -ComputerName sql1,sql2 | Out-Gridview

Gets the SQL Server related services on computers sql1 and sql2, and shows them in a grid view.

#>
	[CmdletBinding()]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("cn","host","Server")]
		[string[]]$ComputerName,
		[PsCredential]$Credential
	)
	
	BEGIN {}
    PROCESS {
        foreach ( $Computer in $ComputerName )
        {
            $Computer = $Computer.split("\")[0]
            $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
            if ( $Server.ComputerName )
	        {
                $Computer = $server.ComputerName
                Write-Verbose "Connecting to $Computer"
                $namespace = Get-CimInstance -ComputerName $Computer -NameSpace root\Microsoft\SQLServer -ClassName "__NAMESPACE" -Filter "Name Like 'ComputerManagement%'" |
                                Sort-Object Name -Descending | Select-Object -First 1
                    Write-Verbose "Getting Cim class SqlService in Namespace $($namespace.Name) on $Computer"
                    try
                    {
                        Get-CimInstance -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -Query "SELECT * FROM SqlService" -ErrorAction SilentlyContinue |
                        Select-Object @{l='ComputerName';e={$_.HostName}}, ServiceName, DisplayName, StartName,
                         @{l='TypeDescr';e={switch($_.SQLServiceType){1 {'Database Engine'} 2 {'SQL Agent'} 3 {'Full Text Search'} 4 {'SSIS'} 5 {'SSAS'} 6 {'SSRS'} 7 {'SQL Browser'} 8 {'Unknown'} 9 {'FullTextFilter Daemon Launcher'}}}},
                         @{l='status';e={switch($_.state){ 1 {'Stopped'} 2 {'Start Pending'}  3 {'Stop Pending' } 4 {'Running'}}}},
                         @{l='startmodus';e={switch($_.startmode){ 1 {'unknown'} 2 {'Automatic'}  3 {'Manual' } 4 {'Disabled'}}}}
                     }
                     catch
                     {
                        Write-Warning "No Sql Services found on $Computer"
                     }
                }
            else
            {
            Write-Warning "Failed to connect to $Computer"
            }
        }
    }
    END {}
}