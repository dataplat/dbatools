function Get-DbaPrivilege
{
  <#
      .SYNOPSIS
      Gets the users with local privileges on one or more computersr. 

      .DESCRIPTION
      Gets the users with local privileges 'Lock Pages in Memory', 'Instant File Initialization', 'Logon as Batch' on one or more computers.

      Requires Local Admin rights on destination computer(s).

      .PARAMETER ComputerName
      The SQL Server (or server in general) that you're connecting to. This command handles named instances.

      .PARAMETER Credential
      Credential object used to connect to the computer as a different user.

      .NOTES
      Author: Klaas Vandenberghe ( @PowerDBAKlaas )
      Tags: Privilege
      dbatools PowerShell module (https://dbatools.io)
      Copyright (C) 2016 Chrissy LeMaire
      This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
      This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
      You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

      .LINK
      https://dbatools.io/Get-DbaPrivilege

      .EXAMPLE
      Get-DbaPrivilege -ComputerName sqlserver2014a

      Gets the local privileges on computer sqlserver2014a.

      .EXAMPLE   
      'sql1','sql2','sql3' | Get-DbaPrivilege

      Gets the local privileges on computers sql1, sql2 and sql3.

      .EXAMPLE
      Get-DbaPrivilege -ComputerName sql1,sql2 | Out-Gridview

      Gets the local privileges on computers sql1 and sql2, and shows them in a grid view.

  #>
  [CmdletBinding()]
  Param (
    [parameter(ValueFromPipeline)]
    [Alias("cn","host","Server")]
    [string[]]$ComputerName = $env:COMPUTERNAME,
    [PSCredential] [System.Management.Automation.CredentialAttribute()]$Credential
  )

BEGIN
  {
    function Convert-SIDToUserName ([string] $SID ) {
      $objSID = New-Object System.Security.Principal.SecurityIdentifier ("$SID") 
      $objUser = $objSID.Translate( [System.Security.Principal.NTAccount]) 
      $objUser.Value
    }
    $FunctionName = (Get-PSCallstack)[0].Command
    $ComputerName = $ComputerName | ForEach-Object {$_.split("\")[0]} | Select-Object -Unique
  }
PROCESS
  {
    foreach ($computer in $ComputerName)
    {
      Write-Verbose "$FunctionName - Connecting to $computer"
      if ( Test-PSRemoting -ComputerName $Computer )
      {
        Write-Verbose "$FunctionName - Getting Privileges on $Computer"
        $Priv = $null
        $Priv = Invoke-Command -ComputerName $computer -ScriptBlock {$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("") ; secedit /export /cfg $temp\secpol.cfg > $NULL ;
        Get-Content $temp\secpol.cfg | Where-Object { $_ -match "SeBatchLogonRight" -or $_ -match 'SeManageVolumePrivilege' -or $_ -match 'SeLockMemoryPrivilege' }}
        try
        {
          Write-Verbose "$FunctionName - Getting Batch Logon Privileges on $Computer"
          $BL = ($Priv | Where-Object {$_ -match "SeBatchLogonRight"}).substring(20).split(",").replace("`*","") | ForEach-Object { Convert-SIDToUserName -SID $_ }
        }
        catch
        {
          Write-Verbose "$FunctionName - No users with Batch Logon Rights on $computer"
        }
        try
        {
          Write-Verbose "$FunctionName - Getting Instant File Initialization Privileges on $Computer"
          $IFI = ($Priv | Where-Object {$_ -like 'SeManageVolumePrivilege*'}).substring(26).split(",").replace("`*","") |  ForEach-Object { Convert-SIDToUserName -SID $_ }
        }
        catch
        {
          Write-Verbose "$FunctionName - No users with Instant File Initialization Rights on $computer"
        }
        try
        {
          Write-Verbose "$FunctionName - Getting Lock Pages in Memory Privileges on $Computer"
          $LPIM = ($Priv | Where-Object {$_ -like 'SeLockMemoryPrivilege*'}).substring(24).split(",").replace("`*","") | ForEach-Object { Convert-SIDToUserName -SID $_ }
        }
        catch
        {
          Write-Verbose "$FunctionName - No users with Lock Pages in Memory Rights on $computer"
        }
        $users = $BL + $IFI + $LPIM | Select-Object -Unique
        $users | ForEach-Object {
          [PSCustomObject]@{
            ComputerName = $computer
            User = $_
            LogonAsBatchPrivilege = $BL -contains $_
            InstantFileInitializationPrivilege = $IFI -contains $_
            LockPagesInMemoryPrivilege = $LPIM -contains $_
          }
        }
        Write-Verbose "$FunctionName - Removing secpol file on $computer"
        Invoke-Command -ComputerName $computer -ScriptBlock {$temp = ([System.IO.Path]::GetTempPath()).TrimEnd("") ; Remove-Item $temp\secpol.cfg -Force > $NULL }
      }
      else
      {
        Write-Warning "$FunctionName - Failed to connect to $Computer"
      }

    }
  }
}
