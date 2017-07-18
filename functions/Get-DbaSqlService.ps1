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

    .PARAMETER Type
    Use -Type to collect only services of the desired SqlServiceType.
    Can be one of the following: "Agent","Browser","Engine","FullText","SSAS","SSIS","SSRS"

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

    .EXAMPLE
    Get-DbaSqlService -ComputerName $MyServers -Type SSRS

    Gets the SQL Server related services of type "SSRS" (Reporting Services) on computers in the variable MyServers.

#>
[CmdletBinding()]
Param (
  [parameter(ValueFromPipeline = $true)]
  [Alias("cn","host","Server")]
  [string[]]$ComputerName = $env:COMPUTERNAME,
  [PSCredential] $Credential,
  [ValidateSet("Agent","Browser","Engine","FullText","SSAS","SSIS","SSRS")][string]$Type
)

BEGIN
  {
  $FunctionName = (Get-PSCallstack)[0].Command
  $ComputerName = $ComputerName | ForEach-Object {$_.split("\")[0]} | Select-Object -Unique
  $TypeClause = switch($Type){ "Agent" {" = 2"} "Browser" {" = 7"} "Engine" {" = 1"} "FulText" {"= 3 OR SQLServiceType = 9"} "SSAS" {" = 5"} "SSIS" {" = 4"} "SSRS" {" = 6"} default {"> 0"} }
  }
PROCESS
  {
        foreach ( $Computer in $ComputerName )
        {
            $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
            if ( $Server.ComputerName )
            {
                $Computer = $server.ComputerName
                Write-Verbose "$FunctionName - Getting SQL Server namespace on $Computer via CIM (WSMan)"
                $namespace = Get-CimInstance -ComputerName $Computer -NameSpace root\Microsoft\SQLServer -ClassName "__NAMESPACE" -Filter "Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue |
                            Where-Object {(Get-CimInstance -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -Query "SELECT * FROM SqlService" -ErrorAction SilentlyContinue).count -gt 0} |
                            Sort-Object Name -Descending | Select-Object -First 1
                if ( $namespace.Name )
                {
                    Write-Verbose "$FunctionName - Getting Cim class SqlService in Namespace $($namespace.Name) on $Computer via CIM (WSMan)"
                    try
                    {
                        Get-CimInstance -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -Query "SELECT * FROM SqlService WHERE SQLServiceType $TypeClause" -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            [PSCustomObject]@{
                                ComputerName = $_.HostName
                                ServiceName = $_.ServiceName
                                DisplayName = $_.DisplayName
                                StartName = $_.StartName
                                ServiceType = switch($_.SQLServiceType){1 {'Database Engine'} 2 {'SQL Agent'} 3 {'Full Text Search'} 4 {'SSIS'} 5 {'SSAS'} 6 {'SSRS'} 7 {'SQL Browser'} 8 {'Unknown'} 9 {'FullTextFilter Daemon Launcher'}}
                                State = switch($_.State){ 1 {'Stopped'} 2 {'Start Pending'}  3 {'Stop Pending' } 4 {'Running'}}
                                StartMode = switch($_.StartMode){ 1 {'Unknown'} 2 {'Automatic'}  3 {'Manual' } 4 {'Disabled'}}
                                }
                            }
                     }
                     catch
                     {
                        Write-Warning "$FunctionName - No Sql Services found on $Computer via CIM (WSMan)"
                     }
                }
                else
                {
                  Write-Verbose "$FunctionName - Getting computer information from $Computer via CIMsession (DCOM)"
                  $sessionoption = New-CimSessionOption -Protocol DCOM
                  $CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
                  if ( $CIMSession )
                  {
                    Write-Verbose "$FunctionName - Get ComputerManagement Namespace in CIMsession on $Computer with protocol DCom."
                    $namespace = Get-CimInstance -CimSession $CIMsession -NameSpace root\Microsoft\SQLServer -ClassName "__NAMESPACE" -Filter "Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue |
                    Where-Object {(Get-CimInstance -CimSession $CIMsession -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -Query "SELECT * FROM SqlService" -ErrorAction SilentlyContinue).count -gt 0} |
                    Sort-Object Name -Descending | Select-Object -First 1
                  }
                  else
                  {
                    Write-Warning "$FunctionName - can't create CIMsession via DCom on $Computer"
                    continue
                  }
                  if ( $namespace.Name )
                  {
                      Write-Verbose "$FunctionName - Getting Cim class SqlService in Namespace $($namespace.Name) on $Computer via CIM (DCOM)"
                      try
                      {
                          Get-CimInstance -CimSession $CIMsession -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -Query "SELECT * FROM SqlService WHERE SQLServiceType $TypeClause" -ErrorAction SilentlyContinue |
                          ForEach-Object {
                              [PSCustomObject]@{
                                  ComputerName = $_.HostName
                                  ServiceName = $_.ServiceName
                                  DisplayName = $_.DisplayName
                                  StartName = $_.StartName
                                  ServiceType = switch($_.SQLServiceType){1 {'Database Engine'} 2 {'SQL Agent'} 3 {'Full Text Search'} 4 {'SSIS'} 5 {'SSAS'} 6 {'SSRS'} 7 {'SQL Browser'} 8 {'Unknown'} 9 {'FullTextFilter Daemon Launcher'}}
                                  State = switch($_.State){ 1 {'Stopped'} 2 {'Start Pending'}  3 {'Stop Pending' } 4 {'Running'}}
                                  StartMode = switch($_.StartMode){ 1 {'Unknown'} 2 {'Automatic'}  3 {'Manual' } 4 {'Disabled'}}
                                  }
                           }
                        }
                        catch
                        {
                          Write-Warning "$FunctionName - No Sql Services found on $Computer via CIM (DCOM)"
                        }
                    if ( $CIMsession ) { Remove-CimSession $CIMsession }
                  }
                  else
                  {
                  Write-Warning "$FunctionName - No ComputerManagement Namespace on $Computer. Please note that this function is available from SQL 2005 up."
                  }
                }
            }
            else
            {
                Write-Warning "$FunctionName - Failed to connect to $Computer"
            }
        }
    }
}
