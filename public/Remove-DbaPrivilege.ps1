function Remove-DbaPrivilege {
    <#
    .SYNOPSIS
        Revokes Windows privileges from SQL Server service accounts or from a specific account.

    .DESCRIPTION
        Removes Windows privileges like Lock Pages in Memory (LPIM), Instant File Initialization (IFI), Logon as Batch, Logon as Service, Generate Security Audits and Create Global Objects from the local security policy. This is the counterpart of Set-DbaPrivilege: it undoes a grant without exporting the policy with secedit, editing the account out of the line by hand and importing it again.

        Without -User, the command discovers the SQL Server engine services on the target computer and revokes the privileges from their service accounts and from their per-service SIDs (NT SERVICE\<ServiceName>). Both are checked for every privilege, because Set-DbaPrivilege grants IFI, LPIM and SecAudit to the per-service SID today but granted them to the service account in earlier versions.

        The built-in accounts LocalSystem, LocalService and NetworkService are skipped during the discovery, because their privileges are shared with every other service that runs under them. To revoke a privilege from one of them anyway, name it with -User.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        The target computer or computers.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Type
        Specifies which Windows privileges to revoke. Accepts one or more values: 'IFI' (Instant File Initialization), 'LPIM' (Lock Pages in Memory), 'BatchLogon' (Log on as a batch job), 'SecAudit' (Generate security audits), 'ServiceLogon' (Log on as a service), and 'CreateGlobalObjects' (Create global objects).
        Revoking ServiceLogon from the account a service runs under keeps that service from starting, so use it only for accounts that no longer run a service.

    .PARAMETER User
        Specifies the account to revoke the privileges from instead of the discovered SQL Server service accounts.
        Accepts domain accounts (DOMAIN\User), local accounts, per-service SIDs (NT SERVICE\MSSQLSERVER) or a SID (S-1-5-...). A SID is useful for an account that was deleted and cannot be resolved by name any more.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Privilege, Security
        Author: the dbatools team + Claude

        Website: https://dbatools.io
        Copyright: (c) 2026 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaPrivilege

    .OUTPUTS
        PSCustomObject

        Returns one object for every privilege that was revoked from an account. A privilege the account did not hold returns no object; the command warns about it instead.

        Properties:
        - ComputerName: The computer the privilege was revoked on
        - User: The account the privilege was revoked from
        - Type: The privilege as named by -Type (IFI, LPIM, BatchLogon, SecAudit, ServiceLogon or CreateGlobalObjects)
        - Privilege: The name of the Windows privilege or right (for example SeManageVolumePrivilege)
        - Status: Always "Removed"

    .EXAMPLE
        PS C:\> Remove-DbaPrivilege -ComputerName sqlserver2014a -Type LPIM,IFI

        Revokes the privileges 'SeLockMemoryPrivilege' and 'SeManageVolumePrivilege' from the SQL Server service accounts and their per-service SIDs on computer sqlserver2014a.

    .EXAMPLE
        PS C:\> Remove-DbaPrivilege -ComputerName sql1 -Type IFI -User "CONTOSO\OldSvc"

        Revokes the privilege 'SeManageVolumePrivilege' from the account CONTOSO\OldSvc on computer sql1.

    .EXAMPLE
        PS C:\> 'sql1','sql2','sql3' | Remove-DbaPrivilege -Type CreateGlobalObjects -User "CONTOSO\BackupAgent" -WhatIf

        Shows which accounts would lose the privilege 'SeCreateGlobalPrivilege' on computers sql1, sql2 and sql3 without changing anything.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [parameter(ValueFromPipeline)]
        [Alias("cn", "host", "Server")]
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Parameter(Mandatory)]
        [ValidateSet("IFI", "LPIM", "BatchLogon", "SecAudit", "ServiceLogon", "CreateGlobalObjects")]
        [string[]]$Type,
        [string]$User,
        [switch]$EnableException
    )

    begin {
        $privilegeNames = @{
            IFI                 = "SeManageVolumePrivilege"
            LPIM                = "SeLockMemoryPrivilege"
            BatchLogon          = "SeBatchLogonRight"
            SecAudit            = "SeAuditPrivilege"
            ServiceLogon        = "SeServiceLogonRight"
            CreateGlobalObjects = "SeCreateGlobalPrivilege"
        }

        # Runs on the target computer: per-service SIDs and local accounts can only be resolved there.
        $removePrivilegesScriptBlock = {
            param (
                $Accounts,
                $Removals,
                $RunToken
            )

            $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
            $cfgFile = "$temp\secpolRemoveByDbatools-$RunToken.cfg"
            $dbFile = "$temp\secpolRemoveByDbatools-$RunToken.sdb"
            $jfmFile = "$temp\secpolRemoveByDbatools-$RunToken.jfm"

            function Resolve-EntrySid ([string]$Entry) {
                if ($Entry -match "^\*?(S-1-[\d-]+)$") {
                    return $Matches[1]
                }
                try {
                    (New-Object System.Security.Principal.NTAccount($Entry)).Translate([System.Security.Principal.SecurityIdentifier]).Value
                } catch {
                    $null
                }
            }

            try {
                $sids = @{ }
                foreach ($account in $Accounts) {
                    $sids[$account] = Resolve-EntrySid -Entry $account
                }

                $null = secedit /export /cfg $cfgFile /areas USER_RIGHTS
                if ($LASTEXITCODE -ne 0) {
                    throw "secedit /export failed with exit code $LASTEXITCODE"
                }
                $content = @(Get-Content -Path $cfgFile)
                $changed = $false

                foreach ($removal in $Removals) {
                    $lineIndex = -1
                    for ($i = 0; $i -lt $content.Count; $i++) {
                        if ($content[$i] -match "^$($removal.Privilege)\s*=") {
                            $lineIndex = $i
                            break
                        }
                    }
                    $entries = @()
                    if ($lineIndex -ge 0) {
                        $entries = @($content[$lineIndex].Split("=", 2)[1].Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    }

                    foreach ($account in $Accounts) {
                        # An entry is either *SID or an account name, and secedit writes a local account by its name
                        # without the computer name. So every entry is compared by its SID, and by its text only when
                        # neither side resolves (an account that no longer exists). The order of the entries is not fixed.
                        $matching = @($entries | Where-Object {
                                $entrySid = Resolve-EntrySid -Entry $_
                                if ($sids[$account] -and $entrySid) {
                                    $entrySid -eq $sids[$account]
                                } else {
                                    $_ -eq $account
                                }
                            })
                        if ($matching.Count -gt 0) {
                            $entries = @($entries | Where-Object { $_ -notin $matching })
                            $changed = $true
                        }
                        [PSCustomObject]@{
                            Account   = $account
                            Type      = $removal.Type
                            Privilege = $removal.Privilege
                            Removed   = $matching.Count -gt 0
                        }
                    }

                    if ($lineIndex -ge 0) {
                        # The line stays in the file even when the list is empty: an empty list revokes the right from everyone.
                        $content[$lineIndex] = "$($removal.Privilege) = $($entries -join ",")"
                    }
                }

                if ($changed) {
                    Set-Content -Path $cfgFile -Value $content -Encoding Unicode
                    $null = secedit /configure /cfg $cfgFile /db $dbFile /areas USER_RIGHTS /overwrite /quiet
                    if ($LASTEXITCODE -ne 0) {
                        throw "secedit /configure failed with exit code $LASTEXITCODE"
                    }
                }
            } finally {
                Remove-Item -Path $cfgFile, $dbFile, $jfmFile -Force -ErrorAction SilentlyContinue
            }
        }

        $ComputerName = $ComputerName.ComputerName | Select-Object -Unique
    }
    process {
        foreach ($computer in $ComputerName) {
            # Asked before the service discovery, which would otherwise run under -WhatIf as well.
            if (Test-Bound -ParameterName User) {
                $targetDescription = $User
            } else {
                $targetDescription = "the SQL Server service accounts"
            }
            if (-not $Pscmdlet.ShouldProcess($computer, "Removing privilege(s) $($Type -join ", ") from $targetDescription")) {
                continue
            }

            $null = Test-ElevationRequirement -ComputerName $computer -Continue
            # Invoke-Command2 executes on the local computer under the process identity and
            # ignores -Credential, so the connectivity test and the service discovery below
            # have to authenticate the same way: with the credential only for remote targets.
            $useCredentialForPreflight = $Credential -and -not ([DbaInstanceParameter]$computer).IsLocalHost
            if ($useCredentialForPreflight) {
                $remotingTestResult = Test-PSRemoting -ComputerName $computer -Credential $Credential
            } else {
                $remotingTestResult = Test-PSRemoting -ComputerName $computer
            }
            if (-not $remotingTestResult) {
                if ($Credential) {
                    Stop-Function -Message "Failed to connect to $computer" -Target $computer -Continue
                } else {
                    Stop-Function -Message "Failed to connect to $computer. If this session itself runs in a remote session (for example via WinRM or Ansible), its network logon cannot authenticate to $computer (double hop). Pass -Credential or connect with an authentication that supports delegation, like CredSSP." -Target $computer -Continue
                }
            }

            $accounts = @()
            if (Test-Bound -ParameterName User) {
                $accounts += $User
            } else {
                Write-Message -Level Verbose -Message "Getting SQL Service Accounts on $computer"
                try {
                    if ($useCredentialForPreflight) {
                        $services = Get-DbaService -ComputerName $computer -Credential $Credential -Type Engine -EnableException
                    } else {
                        $services = Get-DbaService -ComputerName $computer -Type Engine -EnableException
                    }
                } catch {
                    Stop-Function -Message "Failed to get the SQL Server services on $computer" -ErrorRecord $_ -Target $computer -Continue
                }
                foreach ($service in $services) {
                    $accounts += "NT SERVICE\$($service.ServiceName)"
                    if ($service.StartName -match "^(LocalSystem|NT AUTHORITY\\(SYSTEM|LocalService|Local Service|NetworkService|Network Service))$") {
                        Write-Message -Level Verbose -Message "Skipping the built-in account $($service.StartName) of $($service.ServiceName) on $computer, its privileges are shared with other services"
                    } elseif ($service.StartName) {
                        $accounts += $service.StartName
                    }
                }
                # The default virtual account of a service is its per-service SID, so both can be the same.
                $accounts = @($accounts | Sort-Object -Unique)
            }
            if ($accounts.Count -eq 0) {
                Stop-Function -Message "No SQL Service Accounts found on $computer" -Target $computer -Continue
            }

            try {
                $removals = @(foreach ($privilegeType in $Type) {
                        @{
                            Type      = $privilegeType
                            Privilege = $privilegeNames[$privilegeType]
                        }
                    })

                Write-Message -Level Verbose -Message "Removing privilege(s) $($Type -join ", ") from $($accounts -join ", ") on $computer"
                $splatRemovePrivileges = @{
                    Raw          = $true
                    ComputerName = $computer
                    Credential   = $Credential
                    ArgumentList = $accounts, $removals, (Get-Random)
                    ScriptBlock  = $removePrivilegesScriptBlock
                }
                $results = @(Invoke-Command2 @splatRemovePrivileges)

                foreach ($privilegeType in $Type) {
                    $removed = @($results | Where-Object { $PSItem.Type -eq $privilegeType -and $PSItem.Removed })
                    foreach ($result in $removed) {
                        [PSCustomObject]@{
                            ComputerName = $computer
                            User         = $result.Account
                            Type         = $result.Type
                            Privilege    = $result.Privilege
                            Status       = "Removed"
                        }
                    }
                    if ($removed.Count -eq 0) {
                        Write-Message -Level Warning -Message "$($accounts -join ", ") did not hold $privilegeType ($($privilegeNames[$privilegeType])) on $computer, nothing to remove"
                    }
                }
            } catch {
                Stop-Function -Message "Failed to remove the privileges on $computer" -ErrorRecord $_ -Target $computer -Continue
            }
        }
    }
}
