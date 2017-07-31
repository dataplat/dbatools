function Get-DbaServerProtocol
{
<#
    .SYNOPSIS
    Gets the SQL Server related server protocols on a computer. 

    .DESCRIPTION
    Gets the SQL Server related server protocols on one or more computers.

    Requires Local Admin rights on destination computer(s).
    The server protocols can be enabled and disabled when retrieved via WSMan.

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
    https://dbatools.io/Get-DbaServerProtocol

    .EXAMPLE
    Get-DbaServerProtocol -ComputerName sqlserver2014a

    Gets the SQL Server related server protocols on computer sqlserver2014a.

    .EXAMPLE   
    'sql1','sql2','sql3' | Get-DbaServerProtocol

    Gets the SQL Server related server protocols on computers sql1, sql2 and sql3.

    .EXAMPLE
    Get-DbaServerProtocol -ComputerName sql1,sql2 | Out-Gridview

    Gets the SQL Server related server protocols on computers sql1 and sql2, and shows them in a grid view.

    .EXAMPLE
    (Get-DbaServerProtocol -ComputerName sql1 | Where { $_.DisplayName = 'via' }).Disable()

    Disables the VIA ServerNetworkProtocol on computer sql1.
    If succesfull, returncode 0 is shown.

#>
[CmdletBinding()]
Param (
  [parameter(ValueFromPipeline)]
  [Alias("cn","host","Server")]
  [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
  [PSCredential] $Credential
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
                          Where-Object {(Get-CimInstance -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName ServerNetworkProtocol -ErrorAction SilentlyContinue).count -gt 0} |
                          Sort-Object Name -Descending | Select-Object -First 1
              if ( $namespace.Name )
              {
                  Write-Verbose "$FunctionName - Getting Cim class ServerNetworkProtocol in Namespace $($namespace.Name) on $Computer via CIM (WSMan)"
                  try
                  {
                    $prot = Get-CimInstance -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName ServerNetworkProtocol -ErrorAction SilentlyContinue
                    $prot | Add-Member -Force -MemberType ScriptMethod -Name Enable -Value {Invoke-CimMethod -MethodName SetEnable -InputObject $this }
                    $prot | Add-Member -Force -MemberType ScriptMethod -Name Disable -Value {Invoke-CimMethod -MethodName SetDisable -InputObject $this }
                    foreach ( $protocol in $prot ) { Select-DefaultView -InputObject $protocol -Property 'PSComputerName as ComputerName', 'InstanceName', 'ProtocolDisplayName as DisplayName', 'ProtocolName as Name', 'MultiIpconfigurationSupport as MultiIP', 'Enabled as IsEnabled' }
                  }
                  catch
                  {
                    Write-Warning "$FunctionName - No Sql ServerNetworkProtocol found on $Computer via CIM (WSMan)"
                  }
              } #if namespace WSMan
              else
              {
                Write-Verbose "$FunctionName - Getting computer information from $Computer via CIMsession (DCOM)"
                $sessionoption = New-CimSessionOption -Protocol DCOM
                $CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
                if ( $CIMSession )
                {
                  Write-Verbose "$FunctionName - Get ComputerManagement Namespace in CIMsession on $Computer with protocol DCom."
                  $namespace = Get-CimInstance -CimSession $CIMsession -NameSpace root\Microsoft\SQLServer -ClassName "__NAMESPACE" -Filter "Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue |
                  Where-Object {(Get-CimInstance -CimSession $CIMsession -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName ServerNetworkProtocol -ErrorAction SilentlyContinue).count -gt 0} |
                  Sort-Object Name -Descending | Select-Object -First 1
                } #if CIMsession DCom
                else
                {
                  Write-Warning "$FunctionName - can't create CIMsession via DCom on $Computer"
                  continue
                } #else no CIMsession DCom
                if ( $namespace.Name )
                {
                    Write-Verbose "$FunctionName - Getting Cim class ServerNetworkProtocol in Namespace $($namespace.Name) on $Computer via CIM (DCOM)"
                    try
                    {
                      $prot = Get-CimInstance -CimSession $CIMsession -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName ServerNetworkProtocol -ErrorAction SilentlyContinue
                      $prot | Add-Member -Force -MemberType ScriptMethod -Name Enable -Value {Invoke-CimMethod -MethodName SetEnable -InputObject $this }
                      $prot | Add-Member -Force -MemberType ScriptMethod -Name Disable -Value {Invoke-CimMethod -MethodName SetDisable -InputObject $this }
                    foreach ( $protocol in $prot ) { Select-DefaultView -InputObject $protocol -Property 'PSComputerName as ComputerName', 'InstanceName', 'ProtocolDisplayName as DisplayName', 'ProtocolName as Name', 'MultiIpconfigurationSupport as MultiIP', 'Enabled as IsEnabled' }
                    }
                    catch
                    {
                      Write-Warning "$FunctionName - No Sql ServerNetworkProtocol found on $Computer via CIM (DCOM)"
                    }
                if ( $CIMsession ) { Remove-CimSession $CIMsession }
                } #if namespace DCom
                else
                {
                Write-Warning "$FunctionName - No ComputerManagement Namespace on $Computer. Please note that this function is available from SQL 2005 up."
                } #else no namespace DCom
              } #else no namespace WSMan
          } #if computername
          else
          {
              Write-Warning "$FunctionName - Failed to connect to $Computer"
          }
      } #foreach computer
    } #PROCESS
} #function
