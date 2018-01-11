function Get-DbaPrivilege {
    <#
      .SYNOPSIS
      Gets the users with local privileges on one or more computers.

      .DESCRIPTION
      Gets the users with local privileges 'Lock Pages in Memory', 'Instant File Initialization', 'Logon as Batch' on one or more computers.

      Requires Local Admin rights on destination computer(s).

      .PARAMETER ComputerName
      The SQL Server (or server in general) that you're connecting to. This command handles named instances.

      .PARAMETER Credential
      Credential object used to connect to the computer as a different user.

      .PARAMETER EnableException
      By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
      This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
      Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

      .NOTES
      Author: Klaas Vandenberghe ( @PowerDBAKlaas )
      Tags: Privilege
      Website: https://dbatools.io
      Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
      License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

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
        [Alias("cn", "host", "Server")]
        [dbainstanceparameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]
        $Credential,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        $ResolveSID = @"
    function Convert-SIDToUserName ([string] `$SID ) {
      `$objSID = New-Object System.Security.Principal.SecurityIdentifier (`"`$SID`")
      `$objUser = `$objSID.Translate( [System.Security.Principal.NTAccount])
      `$objUser.Value
    }
"@
        $ComputerName = $ComputerName.ComputerName | Select-Object -Unique
    }
    process {
        foreach ($computer in $ComputerName) {
            Write-Message -Level Verbose -Message "Connecting to $computer"
            if (Test-PSRemoting -ComputerName $Computer) {
                Write-Message -Level Verbose -Message "Getting Privileges on $Computer"
                $Priv = $null
                $Priv = Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock {
                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); secedit /export /cfg $temp\secpolByDbatools.cfg > $NULL;
                    Get-Content $temp\secpolByDbatools.cfg | Where-Object { $_ -match "SeBatchLogonRight" -or $_ -match 'SeManageVolumePrivilege' -or $_ -match 'SeLockMemoryPrivilege' }
                }

                Write-Message -Level Verbose -Message "Getting Batch Logon Privileges on $Computer"
                $BL = Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ArgumentList $ResolveSID -ScriptBlock {
                    Param ($ResolveSID)
                    . ([ScriptBlock]::Create($ResolveSID))
                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("");
                    (Get-Content $temp\secpolByDbatools.cfg | Where-Object { $_ -match "SeBatchLogonRight" }).substring(20).split(",").replace("`*", "") |
                        ForEach-Object { Convert-SIDToUserName -SID $_ }
                } -ErrorAction SilentlyContinue
                if ($BL.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Batch Logon Rights on $computer"
                }

                Write-Message -Level Verbose -Message "Getting Instant File Initialization Privileges on $Computer"
                $ifi = Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ArgumentList $ResolveSID -ScriptBlock {
                    Param ($ResolveSID)
                    . ([ScriptBlock]::Create($ResolveSID))
                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("");
                    (Get-Content $temp\secpolByDbatools.cfg | Where-Object { $_ -like 'SeManageVolumePrivilege*' }).substring(26).split(",").replace("`*", "") |
                        ForEach-Object { Convert-SIDToUserName -SID $_ }
                } -ErrorAction SilentlyContinue
                if ($ifi.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Instant File Initialization Rights on $computer"
                }

                Write-Message -Level Verbose -Message "Getting Lock Pages in Memory Privileges on $Computer"
                $lpim = Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ArgumentList $ResolveSID -ScriptBlock {
                    Param ($ResolveSID)
                    . ([ScriptBlock]::Create($ResolveSID))
                    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("");
                    (Get-Content $temp\secpolByDbatools.cfg | Where-Object { $_ -like 'SeLockMemoryPrivilege*' }).substring(24).split(",").replace("`*", "") |
                        ForEach-Object { Convert-SIDToUserName -SID $_ }
                } -ErrorAction SilentlyContinue

                if ($lpim.count -eq 0) {
                    Write-Message -Level Verbose -Message "No users with Lock Pages in Memory Rights on $computer"
                }
                $users = @() + $BL + $ifi + $lpim | Select-Object -Unique
                $users | ForEach-Object {
                    [PSCustomObject]@{
                        ComputerName                       = $computer
                        User                               = $_
                        LogonAsBatchPrivilege              = $BL -contains $_
                        InstantFileInitializationPrivilege = $ifi -contains $_
                        LockPagesInMemoryPrivilege         = $lpim -contains $_
                    }
                }
                Write-Message -Level Verbose -Message "Removing secpol file on $computer"
                Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock { $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); Remove-Item $temp\secpolByDbatools.cfg -Force > $NULL }
            }
            else {
                Write-Message -Level Warning -Message "Failed to connect to $Computer"
            }
        }
    }
}