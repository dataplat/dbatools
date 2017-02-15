Function Get-DbaSqlClientProtocol
{
<#
    .SYNOPSIS
    Gets the SQL Server related client protocols on a computer. 

    .DESCRIPTION
    Gets the SQL Server related client protocols on one or more computers.

    Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
    The SQL Server (or server in general) that you're connecting to. This command handles named instances.

    .PARAMETER Credential
    Credential object used to connect to the computer as a different user.

    .NOTES
    Author: Klaas Vandenberghe ( @PowerDBAKlaas )
    Tags: Protocol
    dbatools PowerShell module (https://dbatools.io)
    Copyright (C) 2016 Chrissy LeMaire
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
    You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

    .LINK
    https://dbatools.io/Get-DbaSqlClientProtocol

    .EXAMPLE
    Get-DbaSqlClientProtocol -ComputerName sqlserver2014a

    Gets the SQL Server related client protocols on computer sqlserver2014a.

    .EXAMPLE   
    'sql1','sql2','sql3' | Get-DbaSqlClientProtocol

    Gets the SQL Server related client protocols on computers sql1, sql2 and sql3.

    .EXAMPLE
    Get-DbaSqlClientProtocol -ComputerName sql1,sql2 | Out-Gridview

    Gets the SQL Server related client protocols on computers sql1 and sql2, and shows them in a grid view.

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
  $FunctionName = (Get-PSCallstack)[0].Command
  $ComputerName = $ComputerName | ForEach-Object {$_.split("\")[0]} | Select-Object -Unique
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
                            Where-Object {(Get-CimInstance -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue).count -gt 0} |
                            Sort-Object Name -Descending | Select-Object -First 1
                if ( $namespace.Name )
                {
                    Write-Verbose "$FunctionName - Getting Cim class ClientNetworkProtocol in Namespace $($namespace.Name) on $Computer via CIM (WSMan)"
                    try
                    {
                        Get-CimInstance -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            [PSCustomObject]@{
                                ComputerName = $_.PSComputerName
                                DisplayName = $_.ProtocolDisplayName
                                ProtocolName = $_.ProtocolName
                                DLL = $_.ProtocolDLL
                                Order = $_.ProtocolOrder
                                IsEnabled = switch ( $_.ProtocolOrder ) { 0 { $false } default { $true } }
                                }
                            }
                     }
                     catch
                     {
                        Write-Warning "$FunctionName - No Sql ClientNetworkProtocol found on $Computer via CIM (WSMan)"
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
                    Where-Object {(Get-CimInstance -CimSession $CIMsession -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue).count -gt 0} |
                    Sort-Object Name -Descending | Select-Object -First 1
                  }
                  else
                  {
                    Write-Warning "$FunctionName - can't create CIMsession via DCom on $Computer"
                    continue
                  }
                  if ( $namespace.Name )
                  {
                      Write-Verbose "$FunctionName - Getting Cim class ClientNetworkProtocol in Namespace $($namespace.Name) on $Computer via CIM (DCOM)"
                      try
                      {
                          Get-CimInstance -CimSession $CIMsession -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName ClientNetworkProtocol -ErrorAction SilentlyContinue |
                          ForEach-Object {
                                [PSCustomObject]@{
                                    ComputerName = $_.PSComputerName
                                    DisplayName = $_.ProtocolDisplayName
                                    ProtocolName = $_.ProtocolName
                                    DLL = $_.ProtocolDLL
                                    Order = $_.ProtocolOrder
                                    IsEnabled = switch ( $_.ProtocolOrder ) { 0 { $false } default { $true } }
                                    }
                           }
                        }
                        catch
                        {
                          Write-Warning "$FunctionName - No Sql ClientNetworkProtocol found on $Computer via CIM (DCOM)"
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
