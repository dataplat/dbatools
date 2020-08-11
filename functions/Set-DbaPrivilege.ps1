function Set-DbaPrivilege {
    <#
    .SYNOPSIS
        Adds the SQL Service account to local privileges on one or more computers.

    .DESCRIPTION
        Adds the SQL Service account to local privileges 'Lock Pages in Memory', 'Instant File Initialization', 'Logon as Batch' on one or more computers.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Type
        Use this to choose the privilege(s) to which you want to add the SQL Service account.
        Accepts 'IFI', 'LPIM', 'BatchLogon', and/or 'SecAudit' for local privileges 'Instant File Initialization', 'Lock Pages in Memory', 'Logon as Batch', and 'Generate Security Audits'.

    .PARAMETER User
        If provided, will add requested permissions to this account instead of the the account under which the SQL service is running.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Privilege
        Author: Klaas Vandenberghe ( @PowerDBAKlaas )

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaPrivilege

    .EXAMPLE
        PS C:\> Set-DbaPrivilege -ComputerName sqlserver2014a -Type LPIM,IFI

        Adds the SQL Service account(s) on computer sqlserver2014a to the local privileges 'SeManageVolumePrivilege' and 'SeLockMemoryPrivilege'.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Set-DbaPrivilege -Type IFI

        Adds the SQL Service account(s) on computers sql1, sql2 and sql3 to the local privilege 'SeManageVolumePrivilege'.

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [dbainstanceparameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Parameter(Mandatory)]
        [ValidateSet('IFI', 'LPIM', 'BatchLogon', 'SecAudit')]
        [string[]]$Type,
        [switch]$EnableException,
        [string]$User
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
            if ($Pscmdlet.ShouldProcess($computer, "Setting Privilege for SQL Service Account")) {
                try {
                    $null = Test-ElevationRequirement -ComputerName $Computer -Continue
                    if (Test-PSRemoting -ComputerName $Computer) {
                        Write-Message -Level Verbose -Message "Exporting Privileges on $Computer"
                        Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock {
                            $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); secedit /export /cfg $temp\secpolByDbatools.cfg > $NULL;
                        }

                        $SQLServiceAccounts = @();
                        if (Test-Bound 'User') {
                            $SQLServiceAccounts += $User;
                        } else {
                            Write-Message -Level Verbose -Message "Getting SQL Service Accounts on $computer"
                            $SQLServiceAccounts += (Get-DbaService -ComputerName $computer -Type Engine).StartName
                        }
                        if ($SQLServiceAccounts.count -ge 1) {
                            Write-Message -Level Verbose -Message "Setting Privileges on $Computer"
                            Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -Verbose -ArgumentList $ResolveAccountToSID, $SQLServiceAccounts, $Type -ScriptBlock {
                                [CmdletBinding()]
                                param ($ResolveAccountToSID,
                                    $SQLServiceAccounts,
                                    $Type
                                )
                                . ([ScriptBlock]::Create($ResolveAccountToSID))
                                $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("");
                                $tempfile = "$temp\secpolByDbatools.cfg"
                                if ('BatchLogon' -in $Type) {
                                    $BLline = Get-Content $tempfile | Where-Object { $_ -match "SeBatchLogonRight" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $BLline) {
                                            $BLline = "SeBatchLogonRight = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$BLline" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Batch Logon Privileges on $env:ComputerName"
                                        } elseif ($BLline -notmatch $SID) {
                                            (Get-Content $tempfile) -replace "SeBatchLogonRight = ", "SeBatchLogonRight = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Batch Logon Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Warning "$acc already has Batch Logon Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                if ('IFI' -in $Type) {
                                    $IFIline = Get-Content $tempfile | Where-Object { $_ -match "SeManageVolumePrivilege" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $IFIline) {
                                            $IFIline = "SeManageVolumePrivilege = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$IFIline" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Instant File Initialization Privileges on $env:ComputerName"
                                        } elseif ($IFIline -notmatch $SID) {
                                            (Get-Content $tempfile) -replace "SeManageVolumePrivilege = ", "SeManageVolumePrivilege = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Instant File Initialization Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Warning "$acc already has Instant File Initialization Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                if ('LPIM' -in $Type) {
                                    $LPIMline = Get-Content $tempfile | Where-Object { $_ -match "SeLockMemoryPrivilege" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $LPIMline) {
                                            $LPIMline = "SeLockMemoryPrivilege = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$LPIMline" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Lock Pages in Memory Privileges on $env:ComputerName"
                                        } elseif ($LPIMline -notmatch $SID) {
                                            (Get-Content $tempfile) -replace "SeLockMemoryPrivilege = ", "SeLockMemoryPrivilege = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Lock Pages in Memory Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Warning "$acc already has Lock Pages in Memory Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                if ('SecAudit' -in $Type) {
                                    $Line = Get-Content $tempfile | Where-Object { $_ -match "SeAuditPrivilege" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $Line) {
                                            $Line = "SeAuditPrivilege = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$Line" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Security Log Privileges on $env:ComputerName"
                                        } elseif ($Line -notmatch $SID) {
                                            (Get-Content $tempfile) -replace "SeAuditPrivilege = ", "SeAuditPrivilege = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Write to Security Log Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Warning "$acc already has Write To Security Audit Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                $null = secedit /configure /cfg $tempfile /db secedit.sdb /areas USER_RIGHTS /overwrite /quiet
                            } -ErrorAction SilentlyContinue
                            Write-Message -Level Verbose -Message "Removing secpol file on $computer"
                            Invoke-Command2 -Raw -ComputerName $computer -Credential $Credential -ScriptBlock { $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); Remove-Item $temp\secpolByDbatools.cfg -Force > $NULL }
                        } else {
                            Write-Message -Level Warning -Message "No SQL Service Accounts found on $Computer"
                        }
                    } else {
                        Write-Message -Level Warning -Message "Failed to connect to $Computer"
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
                }
            }
        }
    }
}