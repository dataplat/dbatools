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

	.PARAMETER Silent
		Use this switch to disable any kind of verbose messages

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
  [ValidateSet("Agent","Browser","Engine","FullText","SSAS","SSIS","SSRS")]
  [string]$Type,
  [switch]$Silent
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
                Write-Message -Level Verbose -Message "Getting SQL Server namespace on $Computer"
                $namespace = Get-DbaCmObject -ComputerName $Computer -NameSpace root\Microsoft\SQLServer -Query "Select * FROM __NAMESPACE WHERE Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue |
                            Where-Object {(Get-DbaCmObject -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -Query "SELECT * FROM SqlService" -ErrorAction SilentlyContinue).count -gt 0} |
                            Sort-Object Name -Descending | Select-Object -First 1
                if ( $namespace.Name )
                {
                    Write-Message -Level Verbose -Message "Getting Cim class SqlService in Namespace $($namespace.Name) on $Computer"
                    try
                    {
                        $services = Get-DbaCmObject -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -Query "SELECT * FROM SqlService WHERE SQLServiceType $TypeClause" -ErrorAction SilentlyContinue
                        ForEach ( $service in $services ) {
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ComputerName -Value $service.HostName
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ServiceName -Value $service.HostName
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ServiceTypeDescr -Value $(switch($service.SQLServiceType){1 {'Database Engine'} 2 {'SQL Agent'} 3 {'Full Text Search'} 4 {'SSIS'} 5 {'SSAS'} 6 {'SSRS'} 7 {'SQL Browser'} 8 {'Unknown'} 9 {'FullTextFilter Daemon Launcher'}})
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name StateDescr -Value $(switch($service.State){ 1 {'Stopped'} 2 {'Start Pending'}  3 {'Stop Pending' } 4 {'Running'}})
                            Add-Member -Force -InputObject $service -MemberType NoteProperty -Name StartModeDescr -Value $(switch($service.StartMode){ 1 {'Unknown'} 2 {'Automatic'}  3 {'Manual' } 4 {'Disabled'}})

                            Select-DefaultView -InputObject $service -Property 'ComputerName','ServiceName', 'DisplayName', 'StartName', 'ServiceTypeDescr', 'StateDescr','StartModedescr'
                            }
                     }
                     catch
                     {
                        Write-Message -Level Warning -Message "No Sql Services found on $Computer"
                     }
                }
                  else
                  {
                    Write-Message -Level Warning -Message "No ComputerManagement Namespace on $Computer. Please note that this function is available from SQL 2005 up."
                  }
            }
            else
            {
                Write-Message -Level Warning -Message "Failed to connect to $Computer"
            }
        }
    }
}