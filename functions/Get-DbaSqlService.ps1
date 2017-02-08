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
		[parameter(ValueFromPipeline = $true)]
		[Alias("cn","host","Server")]
		[string[]]$ComputerName = $env:COMPUTERNAME,
		[PSCredential] [System.Management.Automation.CredentialAttribute()]$Credential
	)
	
BEGIN
    {
    $functionName = "Get-DbaSqlService"
    $ComputerName = $ComputerName | ForEach-Object {$_.split("\")[0]} | Select-Object -Unique
    }
PROCESS
    {
        foreach ( $Computer in $ComputerName )
        {
            $Computer = $Computer.split("\")[0]
            $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
            if ( $Server.ComputerName )
	        {
                $Computer = $server.ComputerName
                Write-Verbose "$functionname - Getting SQL Server namespace on $Computer via CIM (WSMan)"
                $namespace = Get-CimInstance -ComputerName lt-it28 -NameSpace root\Microsoft\SQLServer -ClassName "__NAMESPACE" -Filter "Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue |
                            Where-Object {(Get-CimInstance -ComputerName lt-it28 -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -Query "SELECT * FROM SqlService" -ErrorAction SilentlyContinue).count -gt 0} |
                            Sort-Object Name -Descending | Select-Object -First 1
                if ( $namespace.Name )
                {
                    Write-Verbose "$functionname - Getting Cim class SqlService in Namespace $($namespace.Name) on $Computer via CIM (WSMan)"
                    try
                    {
                        Get-CimInstance -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -Query "SELECT * FROM SqlService" -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            [PSCustomObject]@{
                                ComputerName = $_.HostName
                                ServiceName = $_.ServiceName
                                DisplayName = $_.DisplayName
                                StartName = $_.StartName
                                SQLServiceType = switch($_.SQLServiceType){1 {'Database Engine'} 2 {'SQL Agent'} 3 {'Full Text Search'} 4 {'SSIS'} 5 {'SSAS'} 6 {'SSRS'} 7 {'SQL Browser'} 8 {'Unknown'} 9 {'FullTextFilter Daemon Launcher'}}
                                State = switch($_.State){ 1 {'Stopped'} 2 {'Start Pending'}  3 {'Stop Pending' } 4 {'Running'}}
                                StartMode = switch($_.StartMode){ 1 {'Unknown'} 2 {'Automatic'}  3 {'Manual' } 4 {'Disabled'}}
                                }
                            }
                     }
                     catch
                     {
                        Write-Warning "$functionname - No Sql Services found on $Computer via CIM (WSMan)"
                     }
                }
                else
                {
                    Write-Verbose "$functionname - Getting computer information from $Computer via CIM (DCOM)"
                  $sessionoption = New-CimSessionOption -Protocol DCOM
                  $CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
                  if ( $CIMSession )
                  {
                    $namespace = Get-CimInstance -CimSession $CIMsession -NameSpace root\Microsoft\SQLServer -ClassName "__NAMESPACE" -Filter "Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue |
                    Where-Object {(Get-CimInstance -CimSession $CIMsession -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -Query "SELECT * FROM SqlService" -ErrorAction SilentlyContinue).count -gt 0} |
                    Sort-Object Name -Descending | Select-Object -First 1
                  }
                  else
                  {
                  Write-Warning "$functionName - can't create CIMsession via DCom on $Computer"
                  }
                    if ( $namespace.Name )
                    {
                        Write-Verbose "$functionname - Getting Cim class SqlService in Namespace $($namespace.Name) on $Computer via CIM (DCOM)"
                        try
                        {
                            Get-CimInstance -CimSession $CIMsession -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -Query "SELECT * FROM SqlService" -ErrorAction SilentlyContinue |
                            ForEach-Object {
                                [PSCustomObject]@{
                                    ComputerName = $_.HostName
                                    ServiceName = $_.ServiceName
                                    DisplayName = $_.DisplayName
                                    StartName = $_.StartName
                                    SQLServiceType = switch($_.SQLServiceType){1 {'Database Engine'} 2 {'SQL Agent'} 3 {'Full Text Search'} 4 {'SSIS'} 5 {'SSAS'} 6 {'SSRS'} 7 {'SQL Browser'} 8 {'Unknown'} 9 {'FullTextFilter Daemon Launcher'}}
                                    State = switch($_.State){ 1 {'Stopped'} 2 {'Start Pending'}  3 {'Stop Pending' } 4 {'Running'}}
                                    StartMode = switch($_.StartMode){ 1 {'Unknown'} 2 {'Automatic'}  3 {'Manual' } 4 {'Disabled'}}
                                    }
                                }
                         }
                         catch
                         {
                            Write-Warning "$functionname - No Sql Services found on $Computer via CIM (DCOM)"
                         }
                    }
                }
            }
            else
            {
                Write-Warning "$functionname - Failed to connect to $Computer"
            }
        }
    }
END {}
}