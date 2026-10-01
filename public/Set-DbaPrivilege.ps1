function Set-DbaPrivilege {
    <#
    .SYNOPSIS
        Grants essential Windows privileges to SQL Server service accounts for optimal performance and security.

    .DESCRIPTION
        Configures critical Windows privileges for SQL Server service accounts including Lock Pages in Memory (LPIM), Instant File Initialization (IFI), Logon as Batch, Logon as Service, Generate Security Audits, and Create Global Objects. These privileges are essential for SQL Server performance optimization and proper service operation, eliminating the need to manually configure them through Local Security Policy. The function automatically discovers SQL service accounts on target computers or allows you to specify custom accounts, then uses secedit to update the local security policy.

        Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
        The target SQL Server instance or instances.

    .PARAMETER Credential
        Credential object used to connect to the computer as a different user.

    .PARAMETER Type
        Specifies which Windows privileges to grant to the SQL Server service accounts. Accepts one or more values: 'IFI' (Instant File Initialization), 'LPIM' (Lock Pages in Memory), 'BatchLogon' (Log on as a batch job), 'SecAudit' (Generate security audits), 'ServiceLogon' (Log on as a service), and 'CreateGlobalObjects' (Create global objects).
        These privileges are essential for SQL Server performance and functionality - IFI speeds up database file operations, LPIM prevents memory paging for better performance, the logon rights ensure services can start properly, and CreateGlobalObjects is required by certain backup solutions (e.g. Dell PowerProtect, Redgate, Veritas) whose SQL backup agents need to create named objects in the Global namespace.
        Multiple privileges can be specified together for comprehensive SQL Server optimization.

    .PARAMETER User
        Specifies a custom user account to receive the privileges instead of automatically discovering SQL Server service accounts.
        Use this when you need to grant privileges to a specific account that will run SQL Server services, or when the automatic service account detection doesn't work in your environment.
        Accepts domain accounts (DOMAIN\User), local accounts (COMPUTER\User, .\User or User), per-service SIDs (NT SERVICE\MSSQLSERVER) or a SID (S-1-5-...) - ensure the account exists and will be used by SQL Server services.
        An account that cannot be resolved on the target computer is skipped with a warning.

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
        Author: Klaas Vandenberghe (@PowerDbaKlaas)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaPrivilege

    .OUTPUTS
        None

        This command performs configuration operations and does not return any objects to the pipeline. Status and informational messages are displayed through Write-Message during execution (visible at Verbose level).

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
        [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
        [PSCredential]$Credential,
        [Parameter(Mandatory)]
        [ValidateSet('IFI', 'LPIM', 'BatchLogon', 'SecAudit', 'ServiceLogon', 'CreateGlobalObjects')]
        [string[]]$Type,
        [switch]$EnableException,
        [string]$User
    )

    begin {
        # Dot-sourced into the script block that runs on the target computer, because local accounts and
        # per-service SIDs can only be resolved there.
        $ResolveAccountToSID = @'
function Convert-UserNameToSID ([string] $Acc ) {
    if ($Acc -match "^\*?(S-1-[\d-]+)$") {
        return $Matches[1]
    }
    # The service manager reports the local system account as LocalSystem, and Windows stores a local service
    # account as .\Name. NTAccount translates neither form.
    if ($Acc -eq "LocalSystem") {
        return "S-1-5-18"
    }
    if ($Acc -match "^\.\\(.+)$") {
        $Acc = "$env:COMPUTERNAME\$($Matches[1])"
    }
    try {
        $objUser = New-Object System.Security.Principal.NTAccount("$Acc")
        $strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
        $strSID.Value
    } catch {
        $null
    }
}
function Test-PrivilegeLineHasSid ([string] $Line, [string] $Sid) {
    # An entry is *SID or an account name - secedit exports a local account by its name, without the computer
    # name - so every entry is compared by its SID. A -match on the whole line also took a SID for present
    # when it was only the beginning of another one.
    if (-not $Line) {
        return $false
    }
    foreach ($entry in $Line.Split("=", 2)[1].Split(",")) {
        if ($entry.Trim() -and (Convert-UserNameToSID -Acc $entry.Trim()) -eq $Sid) {
            return $true
        }
    }
    return $false
}
'@
        $ComputerName = $ComputerName.ComputerName | Select-Object -Unique
    }
    process {
        foreach ($computer in $ComputerName) {
            if ($Pscmdlet.ShouldProcess($computer, "Setting Privilege for SQL Service Account")) {
                try {
                    $null = Test-ElevationRequirement -ComputerName $Computer -Continue
                    # Invoke-Command2 executes on the local computer under the process identity and
                    # ignores -Credential, so the connectivity test and the service discovery below
                    # have to authenticate the same way: with the credential only for remote targets.
                    # Otherwise a credential that is valid on the remote computers of a mixed list
                    # but not locally would reject the local computer although the actual operation
                    # would succeed. Without a credential the implicit identity is used, which fails
                    # when it cannot authenticate to the target (double hop).
                    $useCredentialForPreflight = $Credential -and -not ([DbaInstanceParameter]$computer).IsLocalHost
                    if ($useCredentialForPreflight) {
                        $remotingTestResult = Test-PSRemoting -ComputerName $Computer -Credential $Credential
                    } else {
                        $remotingTestResult = Test-PSRemoting -ComputerName $Computer
                    }
                    if ($remotingTestResult) {
                        Write-Message -Level Verbose -Message "Exporting Privileges on $Computer"
                        # A random token keeps this invocation's secedit cfg/db/jfm files from colliding with
                        # (or being deleted by) another concurrent Set-DbaPrivilege run against the same computer.
                        $seceditRunToken = Get-Random
                        $exportPrivilegesScriptBlock = {
                            param ($ExportRunToken)
                            $temp = ([System.IO.Path]::GetTempPath()).TrimEnd(""); secedit /export /cfg $temp\secpolByDbatools-$ExportRunToken.cfg > $NULL;
                        }
                        $splatExportPrivileges = @{
                            Raw          = $true
                            ComputerName = $computer
                            Credential   = $Credential
                            ArgumentList = $seceditRunToken
                            ScriptBlock  = $exportPrivilegesScriptBlock
                        }
                        Invoke-Command2 @splatExportPrivileges

                        $SQLServiceAccounts = @()
                        $SQLPerServiceSIDs = @()
                        if (Test-Bound 'User') {
                            $SQLServiceAccounts += $User
                            $SQLPerServiceSIDs += $User
                        } else {
                            Write-Message -Level Verbose -Message "Getting SQL Service Accounts on $computer"
                            if ($useCredentialForPreflight) {
                                $services = Get-DbaService -ComputerName $computer -Credential $Credential -Type Engine
                            } else {
                                $services = Get-DbaService -ComputerName $computer -Type Engine
                            }
                            $SQLServiceAccounts += $services.StartName
                            # Per-service SIDs (NT SERVICE\<ServiceName>) are added to the service token by Windows
                            # for all services on Vista/Server 2008 and later. SQL Server uses the per-service SID
                            # for file operations (IFI) and memory operations (LPIM), matching setup.exe behavior.
                            $SQLPerServiceSIDs += $services | ForEach-Object { "NT SERVICE\$($_.ServiceName)" }
                        }
                        # Instances that run under the same account list it once each. The script block below checks
                        # each account against the privilege line it read before adding, so a repeated account was added twice.
                        $SQLServiceAccounts = @($SQLServiceAccounts | Select-Object -Unique)
                        $SQLPerServiceSIDs = @($SQLPerServiceSIDs | Select-Object -Unique)
                        if ($SQLServiceAccounts.count -ge 1) {
                            Write-Message -Level Verbose -Message "Setting Privileges on $Computer"
                            $setPrivilegesScriptBlock = {
                                [CmdletBinding()]
                                param ($ResolveAccountToSID,
                                    $SQLServiceAccounts,
                                    $SQLPerServiceSIDs,
                                    $Type,
                                    $ConfigureRunToken
                                )
                                . ([ScriptBlock]::Create($ResolveAccountToSID))
                                $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("");
                                $tempfile = "$temp\secpolByDbatools-$ConfigureRunToken.cfg"
                                if ('BatchLogon' -in $Type) {
                                    $BLline = Get-Content $tempfile | Where-Object { $_ -match "SeBatchLogonRight" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $SID) {
                                            # Without a SID the line would get an empty *, or the SID of the previous account.
                                            Write-Warning "Cannot resolve $acc to a SID on $env:ComputerName, so it was not added"
                                            continue
                                        }
                                        if (-not $BLline) {
                                            $BLline = "SeBatchLogonRight = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$BLline" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Batch Logon Privileges on $env:ComputerName"
                                        } elseif (-not (Test-PrivilegeLineHasSid -Line $BLline -Sid $SID)) {
                                            (Get-Content $tempfile) -replace "SeBatchLogonRight = ", "SeBatchLogonRight = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Batch Logon Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "$acc already has Batch Logon Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                if ('IFI' -in $Type) {
                                    $IFIline = Get-Content $tempfile | Where-Object { $_ -match "SeManageVolumePrivilege" }
                                    # Use per-service SIDs for IFI: SQL Server uses the NT SERVICE\<ServiceName>
                                    # SID for volume maintenance tasks, matching SQL Server setup.exe behavior.
                                    ForEach ($acc in $SQLPerServiceSIDs) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $SID) {
                                            # Without a SID the line would get an empty *, or the SID of the previous account.
                                            Write-Warning "Cannot resolve $acc to a SID on $env:ComputerName, so it was not added"
                                            continue
                                        }
                                        if (-not $IFIline) {
                                            $IFIline = "SeManageVolumePrivilege = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$IFIline" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Instant File Initialization Privileges on $env:ComputerName"
                                        } elseif (-not (Test-PrivilegeLineHasSid -Line $IFIline -Sid $SID)) {
                                            (Get-Content $tempfile) -replace "SeManageVolumePrivilege = ", "SeManageVolumePrivilege = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Instant File Initialization Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "$acc already has Instant File Initialization Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                if ('LPIM' -in $Type) {
                                    $LPIMline = Get-Content $tempfile | Where-Object { $_ -match "SeLockMemoryPrivilege" }
                                    # Use per-service SIDs for LPIM: SQL Server uses the NT SERVICE\<ServiceName>
                                    # SID for locked memory pages, matching SQL Server setup.exe behavior.
                                    ForEach ($acc in $SQLPerServiceSIDs) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $SID) {
                                            # Without a SID the line would get an empty *, or the SID of the previous account.
                                            Write-Warning "Cannot resolve $acc to a SID on $env:ComputerName, so it was not added"
                                            continue
                                        }
                                        if (-not $LPIMline) {
                                            $LPIMline = "SeLockMemoryPrivilege = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$LPIMline" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Lock Pages in Memory Privileges on $env:ComputerName"
                                        } elseif (-not (Test-PrivilegeLineHasSid -Line $LPIMline -Sid $SID)) {
                                            (Get-Content $tempfile) -replace "SeLockMemoryPrivilege = ", "SeLockMemoryPrivilege = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Lock Pages in Memory Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "$acc already has Lock Pages in Memory Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                if ('SecAudit' -in $Type) {
                                    $SALine = Get-Content $tempfile | Where-Object { $_ -match "SeAuditPrivilege" }
                                    # Use per-service SIDs for SecAudit: SQL Server uses the NT SERVICE\<ServiceName>
                                    # SID when writing security audit events, matching SQL Server setup.exe behavior.
                                    ForEach ($acc in $SQLPerServiceSIDs) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $SID) {
                                            # Without a SID the line would get an empty *, or the SID of the previous account.
                                            Write-Warning "Cannot resolve $acc to a SID on $env:ComputerName, so it was not added"
                                            continue
                                        }
                                        if (-not $SALine) {
                                            $SALine = "SeAuditPrivilege = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$SALine" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Security Log Privileges on $env:ComputerName"
                                        } elseif (-not (Test-PrivilegeLineHasSid -Line $SALine -Sid $SID)) {
                                            (Get-Content $tempfile) -replace "SeAuditPrivilege = ", "SeAuditPrivilege = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Write to Security Log Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "$acc already has Write To Security Audit Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                if ('ServiceLogon' -in $Type) {
                                    $SLline = Get-Content $tempfile | Where-Object { $_ -match "SeServiceLogonRight" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $SID) {
                                            # Without a SID the line would get an empty *, or the SID of the previous account.
                                            Write-Warning "Cannot resolve $acc to a SID on $env:ComputerName, so it was not added"
                                            continue
                                        }
                                        if (-not $SLline) {
                                            $SLline = "SeServiceLogonRight = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$SLline" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Service Logon Privileges on $env:ComputerName"
                                        } elseif (-not (Test-PrivilegeLineHasSid -Line $SLline -Sid $SID)) {
                                            (Get-Content $tempfile) -replace "SeServiceLogonRight = ", "SeServiceLogonRight = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Service Logon Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "$acc already has Service Logon Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                if ('CreateGlobalObjects' -in $Type) {
                                    $CGOline = Get-Content $tempfile | Where-Object { $_ -match "SeCreateGlobalPrivilege" }
                                    ForEach ($acc in $SQLServiceAccounts) {
                                        $SID = Convert-UserNameToSID -Acc $acc;
                                        if (-not $SID) {
                                            # Without a SID the line would get an empty *, or the SID of the previous account.
                                            Write-Warning "Cannot resolve $acc to a SID on $env:ComputerName, so it was not added"
                                            continue
                                        }
                                        if (-not $CGOline) {
                                            $CGOline = "SeCreateGlobalPrivilege = *$SID"
                                            (Get-Content $tempfile) -replace "\[Privilege Rights\]", "[Privilege Rights]`n$CGOline" |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Create Global Objects Privileges on $env:ComputerName"
                                        } elseif (-not (Test-PrivilegeLineHasSid -Line $CGOline -Sid $SID)) {
                                            (Get-Content $tempfile) -replace "SeCreateGlobalPrivilege = ", "SeCreateGlobalPrivilege = *$SID," |
                                                Set-Content $tempfile
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "Added $acc to Create Global Objects Privileges on $env:ComputerName"
                                        } else {
                                            <# DO NOT use Write-Message as this is inside of a script block #>
                                            Write-Verbose "$acc already has Create Global Objects Privilege on $env:ComputerName"
                                        }
                                    }
                                }
                                $null = secedit /configure /cfg $tempfile /db $temp\secedit-$ConfigureRunToken.sdb /areas USER_RIGHTS /overwrite /quiet
                            }
                            $splatSetPrivileges = @{
                                Raw          = $true
                                ComputerName = $computer
                                Credential   = $Credential
                                Verbose      = $true
                                ArgumentList = $ResolveAccountToSID, $SQLServiceAccounts, $SQLPerServiceSIDs, $Type, $seceditRunToken
                                ScriptBlock  = $setPrivilegesScriptBlock
                            }
                            Invoke-Command2 @splatSetPrivileges

                            Write-Message -Level Verbose -Message "Removing secpol file on $computer"
                            $removeSecpolScriptBlock = {
                                param ($CleanupRunToken)
                                $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("")
                                # secedit's /configure /db creates a database file plus a matching .jfm journal
                                # file next to it; both live in $temp now instead of leaking into the caller's cwd.
                                $splatRemoveSeceditFiles = @{
                                    Path        = "$temp\secpolByDbatools-$CleanupRunToken.cfg", "$temp\secedit-$CleanupRunToken.sdb", "$temp\secedit-$CleanupRunToken.jfm"
                                    Force       = $true
                                    ErrorAction = "SilentlyContinue"
                                }
                                Remove-Item @splatRemoveSeceditFiles > $NULL
                            }
                            $splatRemoveSecpolFile = @{
                                Raw          = $true
                                ComputerName = $computer
                                Credential   = $Credential
                                ArgumentList = $seceditRunToken
                                ScriptBlock  = $removeSecpolScriptBlock
                            }
                            Invoke-Command2 @splatRemoveSecpolFile
                        } else {
                            Write-Message -Level Warning -Message "No SQL Service Accounts found on $Computer"
                        }
                    } else {
                        if ($Credential) {
                            Write-Message -Level Warning -Message "Failed to connect to $Computer"
                        } else {
                            Write-Message -Level Warning -Message "Failed to connect to $Computer. If this session itself runs in a remote session (for example via WinRM or Ansible), its network logon cannot authenticate to $Computer (double hop). Pass -Credential or connect with an authentication that supports delegation, like CredSSP."
                        }
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $computer -Continue
                }
            }
        }
    }
}
