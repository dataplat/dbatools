function Set-DbaPrivilege {
    <#
      .SYNOPSIS
      Adds the SQL Service account to local privileges on one or more computers.

      .DESCRIPTION
      Adds the SQL Service account to local privileges 'Lock Pages in Memory', 'Instant File Initialization', 'Logon as Batch' on one or more computers.

      Requires Local Admin rights on destination computer(s).

      .PARAMETER ComputerName
      The SQL Server (or server in general) that you're connecting to. This command handles named instances.

      .PARAMETER Credential
      Credential object used to connect to the computer as a different user.

      .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

      .PARAMETER Type
      Use this to choose the privilege(s) to which you want to add the SQL Service account.
      Accepts 'IFI', 'LPIM' and/or 'BatchLogon' for local privileges 'Instant File Initialization', 'Lock Pages in Memory' and 'Logon as Batch'.

      .NOTES
      Author: Klaas Vandenberghe ( @PowerDBAKlaas )
      Tags: Privilege
      Website: https://dbatools.io
      Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
      License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
      https://dbatools.io/Set-DbaPrivilege

      .EXAMPLE
      Set-DbaPrivilege -ComputerName sqlserver2014a -Type LPIM,IFI

      Adds the SQL Service account(s) on computer sqlserver2014a to the local privileges 'SeManageVolumePrivilege' and 'SeLockMemoryPrivilege'.

      .EXAMPLE
      'sql1','sql2','sql3' | Set-DbaPrivilege -Type IFI

      Adds the SQL Service account(s) on computers sql1, sql2 and sql3 to the local privilege 'SeManageVolumePrivilege'.

  #>
    [CmdletBinding()]
    Param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [dbainstanceparameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Parameter(Mandatory = $true)]
        [ValidateSet('IFI', 'LPIM', 'BatchLogon')]
        [string[]]$Type,
        [switch][Alias('Silent')]
        $EnableException
    )
    
    begin {
        $ResolveAccountToSID = @"
function Convert-UserNameToSID ([string] `$Acc ) {
`$objUser = New-Object System.Security.Principal.NTAccount(`"`$Acc`")
`$strSID = `$objUser.Translate([System.Security.Principal.SecurityIdentifier])
`$strSID.Value
}
"@
        $ComputerName = $ComputerName.ComputerName | Select-Object -Unique
    }
    process {
        foreach ($computer in $ComputerName) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $computer"
                $null = Test-ElevationRequirement -ComputerName $Computer -Continue
                if (Test-PSRemoting -ComputerName $Computer) {
                    Write-Message -Level Verbose -Message "Exporting Privileges on $Computer"
                    Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock {
                        $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); secedit /export /cfg $temp\secpolByDbatools.cfg > $NULL;
                    }
                    Write-Message -Level Verbose -Message "Getting SQL Service Accounts on $computer"
                    $SQLServiceAccounts = (Get-DbaSqlService -ComputerName $computer -Type Engine).StartName
                    if ($SQLServiceAccounts.count -ge 1) {
                        Write-Message -Level Verbose -Message "Setting Privileges on $Computer"
                        Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -Verbose -ArgumentList $ResolveAccountToSID, $SQLServiceAccounts, $BatchLogon, $IFI, $LPIM -ScriptBlock {
                            [CmdletBinding()]
                            Param ($ResolveAccountToSID,
                                $SQLServiceAccounts,
                                $BatchLogon,
                                $IFI,
                                $LPIM)
                            . ([ScriptBlock]::Create($ResolveAccountToSID))
                            $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("");
                            $tempfile = "$temp\secpolByDbatools.cfg"
                            if ('BatchLogon' -in $Type) {
                                $BLline = Get-Content $tempfile | Where-Object { $_ -match "SeBatchLogonRight" }
                                ForEach ($acc in $SQLServiceAccounts) {
                                    $SID = Convert-UserNameToSID -Acc $acc;
                                    if ($BLline -notmatch $SID) {
                                        (Get-Content $tempfile) -replace "SeBatchLogonRight = ", "SeBatchLogonRight = *$SID," |
                                        Set-Content $tempfile
                                        Write-Verbose "Added $acc to Batch Logon Privileges on $env:ComputerName"
                                    }
                                    else {
                                        Write-Warning "$acc already has Batch Logon Privilege on $env:ComputerName"
                                    }
                                }
                            }
                            if ('IFI' -in $Type) {
                                $IFIline = Get-Content $tempfile | Where-Object { $_ -match "SeManageVolumePrivilege" }
                                ForEach ($acc in $SQLServiceAccounts) {
                                    $SID = Convert-UserNameToSID -Acc $acc;
                                    if ($IFIline -notmatch $SID) {
                                        (Get-Content $tempfile) -replace "SeManageVolumePrivilege = ", "SeManageVolumePrivilege = *$SID," |
                                        Set-Content $tempfile
                                        Write-Verbose "Added $acc to Instant File Initialization Privileges on $env:ComputerName"
                                    }
                                    else {
                                        Write-Warning "$acc already has Instant File Initialization Privilege on $env:ComputerName"
                                    }
                                }
                            }
                            if ('LPIM' -in $Type) {
                                $LPIMline = Get-Content $tempfile | Where-Object { $_ -match "SeLockMemoryPrivilege" }
                                ForEach ($acc in $SQLServiceAccounts) {
                                    $SID = Convert-UserNameToSID -Acc $acc;
                                    if ($LPIMline -notmatch $SID) {
                                        (Get-Content $tempfile) -replace "SeLockMemoryPrivilege = ", "SeLockMemoryPrivilege = *$SID," |
                                        Set-Content $tempfile
                                        Write-Verbose "Added $acc to Lock Pages in Memory Privileges on $env:ComputerName"
                                    }
                                    else {
                                        Write-Warning "$acc already has Lock Pages in Memory Privilege on $env:ComputerName"
                                    }
                                }
                            }
                            $null = secedit /configure /cfg $tempfile /db secedit.sdb /areas USER_RIGHTS /overwrite /quiet
                        } -ErrorAction SilentlyContinue
                        Write-Message -Level Verbose -Message "Removing secpol file on $computer"
                        Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock { $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); Remove-Item $temp\secpolByDbatools.cfg -Force > $NULL }
                    }
                    else {
                        Write-Message -Level Warning -Message "No SQL Service Accounts found on $Computer"
                    }
                }
                else {
                    Write-Message -Level Warning -Message "Failed to connect to $Computer"
                }
            }
            catch {
                Stop-Function -Continue -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}