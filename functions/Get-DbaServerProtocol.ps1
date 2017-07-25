Function Get-DbaServerProtocol
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

	.PARAMETER Silent
		Use this switch to disable any kind of verbose messages

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
  [string[]]$ComputerName = $env:COMPUTERNAME,
  [PSCredential] $Credential,
  [switch]$Silent
)

BEGIN
  {
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
				Write-Message -Level Verbose -Message "Getting SQL Server namespace on $computer"
              $namespace = Get-DbaCmObject -ComputerName $Computer -NameSpace root\Microsoft\SQLServer -Query "Select * FROM __NAMESPACE WHERE Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue |
                          Where-Object {(Get-DbaCmObject -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -ClassName ServerNetworkProtocol -ErrorAction SilentlyContinue).count -gt 0} |
                          Sort-Object Name -Descending | Select-Object -First 1
              if ( $namespace.Name )
              {
                  Write-Message -Level Verbose -Message "Getting Cim class ServerNetworkProtocol in Namespace $($namespace.Name) on $Computer"
                  try
                  {
                    $prot = Get-DbaCmObject -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -ClassName ServerNetworkProtocol -ErrorAction SilentlyContinue
                    $prot | Add-Member -Force -MemberType ScriptMethod -Name Enable -Value {Invoke-CimMethod -MethodName SetEnable -InputObject $this }
                    $prot | Add-Member -Force -MemberType ScriptMethod -Name Disable -Value {Invoke-CimMethod -MethodName SetDisable -InputObject $this }
                    foreach ( $protocol in $prot ) { Select-DefaultView -InputObject $protocol -Property 'PSComputerName as ComputerName', 'InstanceName', 'ProtocolDisplayName as DisplayName', 'ProtocolName as Name', 'MultiIpconfigurationSupport as MultiIP', 'Enabled as IsEnabled' }
                  }
                  catch
                  {
                    Write-Message -Level Warning -Message "No Sql ServerNetworkProtocol found on $Computer"
                  }
              } #if namespace
                else
                {
                Write-Message -Level Warning -Message "No ComputerManagement Namespace on $Computer. Please note that this function is available from SQL 2005 up."
                } #else no namespace
          } #if computername
          else
          {
              Write-Message -Level Warning -Message "Failed to connect to $Computer"
          }
      } #foreach computer
    } #PROCESS
} #function
