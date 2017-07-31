function Get-DbaNetworkActivity
{
  <#
      .SYNOPSIS
      Gets the Current traffic on every Network Interface on a computer.

      .DESCRIPTION
      Gets the Current traffic on every Network Interface on a computer.
      See https://msdn.microsoft.com/en-us/library/aa394293(v=vs.85).aspx

      Requires Local Admin rights on destination computer(s).

      .PARAMETER ComputerName
      The SQL Server (or server in general) that you're connecting to. This command handles named instances.

      .PARAMETER Credential
      Credential object used to connect to the computer as a different user.

      .NOTES
      Author: Klaas Vandenberghe ( @PowerDBAKlaas )
      Tags: Network
      dbatools PowerShell module (https://dbatools.io)
      Copyright (C) 2016 Chrissy LeMaire
      This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
      This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
      You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

      .LINK
      https://dbatools.io/Get-DbaNetworkActivity

      .EXAMPLE
      Get-DbaNetworkActivity -ComputerName sqlserver2014a
      
      Gets the Current traffic on every Network Interface on computer sqlserver2014a.

      .EXAMPLE   
      'sql1','sql2','sql3' | Get-DbaNetworkActivity
      
      Gets the Current traffic on every Network Interface on computers sql1, sql2 and sql3.

      .EXAMPLE
      Get-DbaNetworkActivity -ComputerName sql1,sql2 | Out-Gridview

      Gets the Current traffic on every Network Interface on computers sql1 and sql2, and shows them in a grid view.

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
    $sessionoption = New-CimSessionOption -Protocol DCom
  }
  PROCESS
  {
    foreach ($computer in $ComputerName)
    {
      $props = @{ "ComputerName" = $computer }
      $Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
      if ( $Server.ComputerName )
      {
        $Computer = $server.ComputerName
        Write-Verbose "$FunctionName - Creating CIMSession on $computer over WSMan"
        $CIMsession = New-CimSession -ComputerName $Computer -ErrorAction SilentlyContinue -Credential $Credential
        if ( -not $CIMSession )
        {
          Write-Verbose "$FunctionName - Creating CIMSession on $computer over WSMan failed. Creating CIMSession on $computer over DCom"
          $CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
        }
        if ( $CIMSession )
        {
          Write-Verbose "$FunctionName - Getting properties for Network Interfaces on $computer"
          $NICs = Get-CimInstance -CimSession $CIMSession -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface
        $NICs | Add-Member -Force -MemberType ScriptProperty -Name ComputerName -Value { $computer }
          $NICs | Add-Member -Force -MemberType ScriptProperty -Name Bandwith -Value { switch  ( $this.CurrentBandWidth ) { 10000000000 { '10Gb' } 1000000000 { '1Gb' } 100000000 { '100Mb' } 10000000 { '10Mb' } 1000000 { '1Mb' } 100000 { '100Kb' } default { 'Low' } } }
          foreach ( $NIC in $NICs ) { Select-DefaultView -InputObject $NIC -Property 'ComputerName', 'Name as NIC', 'BytesReceivedPersec', 'BytesSentPersec', 'BytesTotalPersec', 'Bandwith'}
        } #if CIMSession
        else
        {
          Write-Warning "$FunctionName - Can't create CIMSession on $computer"
        }
      } #if computername
      else
      {
        Write-Warning "$FunctionName - can't connect to $computer"
      }
    } #foreach computer
  } #PROCESS
} #function
