#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaPrivilege",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "Type",
                "EnableException",
                "User"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

InModuleScope dbatools {
    Describe "Set-DbaPrivilege regressions" -Tag UnitTests {
        BeforeAll {
            function secedit {
                param(
                    [Parameter(ValueFromRemainingArguments)]
                    [object[]]$ArgumentList
                )
            }
        }

        BeforeEach {
            $script:policyFile = $null
            $script:capturedPolicyContent = $null
            # What the mocked secedit /export writes; a test replaces it to start from other entries.
            $script:exportedPolicyContent = @(
                "[Privilege Rights]"
                "SeCreateGlobalPrivilege = "
            )

            Mock Test-ElevationRequirement { $true }
            Mock Test-PSRemoting { $true }
            Mock Invoke-Command2 {
                param(
                    $ComputerName,
                    $Credential,
                    $ScriptBlock,
                    $ArgumentList
                )

                # Set-DbaPrivilege passes the same per-run token to every call it makes (export,
                # configure, cleanup); it is always the last element so this reads it regardless of
                # whether $ArgumentList is that lone token or the configure call's 5-element list.
                $runToken = if ($ArgumentList -is [array]) { $ArgumentList[-1] } else { $ArgumentList }
                $script:policyFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "secpolByDbatools-$runToken.cfg"

                if ($ScriptBlock.ToString() -match "secedit /export /cfg") {
                    Set-Content -Path $script:policyFile -Value $script:exportedPolicyContent
                    return
                }

                if ($ScriptBlock.ToString() -match "secedit /configure") {
                    & $ScriptBlock @ArgumentList
                    $script:capturedPolicyContent = Get-Content -Path $script:policyFile
                    return
                }

                Remove-Item -Path $script:policyFile -Force -ErrorAction SilentlyContinue
            }
        }

        AfterEach {
            Remove-Item -Path $script:policyFile -Force -ErrorAction SilentlyContinue
        }

        It "adds CreateGlobalObjects when the privilege entry exists but is empty" {
            $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $expectedSid = ([System.Security.Principal.NTAccount]$user).Translate([System.Security.Principal.SecurityIdentifier]).Value

            $splatSetPrivilege = @{
                ComputerName = $env:COMPUTERNAME
                Type         = "CreateGlobalObjects"
                User         = $user
                Confirm      = $false
            }
            $null = Set-DbaPrivilege @splatSetPrivilege

            ($script:capturedPolicyContent | Where-Object { $PSItem -match "^SeCreateGlobalPrivilege" }) |
                Should -Match "^SeCreateGlobalPrivilege = \*$([regex]::Escape($expectedSid))(,)?$"
        }

        It "grants to LocalSystem as the SID of the local system account" {
            # The service manager reports the local system account as LocalSystem, which NTAccount cannot translate.
            $null = Set-DbaPrivilege -ComputerName $env:COMPUTERNAME -Type CreateGlobalObjects -User LocalSystem -Confirm:$false

            ($script:capturedPolicyContent | Where-Object { $PSItem -match "^SeCreateGlobalPrivilege" }) |
                Should -Match "^SeCreateGlobalPrivilege = \*S-1-5-18(,)?$"
        }

        It "adds an account whose SID is only the beginning of an entry that is already there" {
            # The check was -notmatch on the whole line, so *S-...-5001 counted as the account S-...-500.
            $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $userSid = ([System.Security.Principal.NTAccount]$user).Translate([System.Security.Principal.SecurityIdentifier]).Value
            $script:exportedPolicyContent = @(
                "[Privilege Rights]"
                "SeCreateGlobalPrivilege = *$($userSid)1"
            )

            $null = Set-DbaPrivilege -ComputerName $env:COMPUTERNAME -Type CreateGlobalObjects -User $user -Confirm:$false

            $entries = ($script:capturedPolicyContent | Where-Object { $PSItem -match "^SeCreateGlobalPrivilege" }).Split("=", 2)[1].Split(",").Trim()
            $entries | Should -Contain "*$userSid"
            $entries | Should -Contain "*$($userSid)1"
        }

        It "does not add an account again that is already listed by its name" {
            # secedit exports a local account by its name, which a comparison by SID text did not recognize.
            $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $script:exportedPolicyContent = @(
                "[Privilege Rights]"
                "SeCreateGlobalPrivilege = $user"
            )

            $null = Set-DbaPrivilege -ComputerName $env:COMPUTERNAME -Type CreateGlobalObjects -User $user -Confirm:$false

            ($script:capturedPolicyContent | Where-Object { $PSItem -match "^SeCreateGlobalPrivilege" }) | Should -Be "SeCreateGlobalPrivilege = $user"
        }

        It "warns and adds nothing for an account that cannot be resolved" {
            # Without a SID the line got an empty * entry, or the SID of the account before.
            $splatSetUnknown = @{
                ComputerName    = $env:COMPUTERNAME
                Type            = "CreateGlobalObjects"
                User            = "dbatoolsci_nosuchuser_$(Get-Random)"
                Confirm         = $false
                WarningVariable = "unknownWarning"
                WarningAction   = "SilentlyContinue"
            }
            $null = Set-DbaPrivilege @splatSetUnknown

            ($script:capturedPolicyContent | Where-Object { $PSItem -match "^SeCreateGlobalPrivilege" }) | Should -Be "SeCreateGlobalPrivilege = "
            $unknownWarning | Should -BeLike "*Cannot resolve dbatoolsci_nosuchuser_*"
        }

        It "passes the credential to the remoting connectivity test and the service discovery for a remote computer" {
            # Regression test: neither Test-PSRemoting nor Get-DbaService received the credential,
            # so both authenticated with the implicit identity and failed although the credential
            # would have worked - for example when the caller itself runs in a remoting session
            # with a network logon token (double hop).
            $script:mockServiceUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            Mock Get-DbaService {
                [PSCustomObject]@{
                    StartName   = $script:mockServiceUser
                    ServiceName = "MSSQLSERVER"
                }
            }
            $testCredential = New-Object System.Management.Automation.PSCredential ("dbatoolsTestUser", (ConvertTo-SecureString -String "dummy" -AsPlainText -Force))

            $splatSetPrivilege = @{
                ComputerName = "dbatoolsTestRemote"
                Type         = "ServiceLogon"
                Credential   = $testCredential
                Confirm      = $false
            }
            $null = Set-DbaPrivilege @splatSetPrivilege

            Should -Invoke Test-PSRemoting -Times 1 -Exactly -ParameterFilter { $Credential -eq $testCredential }
            Should -Invoke Get-DbaService -Times 1 -Exactly -ParameterFilter { $Credential -eq $testCredential }
        }

        It "does not pass the credential to the connectivity test and the service discovery for the local computer" {
            # Invoke-Command2 runs locally under the process identity and ignores -Credential, so
            # the pre-flight and the service discovery have to do the same - a credential that is
            # valid remotely but not locally must not reject the local computer of a mixed list.
            $script:mockServiceUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            Mock Get-DbaService {
                [PSCustomObject]@{
                    StartName   = $script:mockServiceUser
                    ServiceName = "MSSQLSERVER"
                }
            }
            $testCredential = New-Object System.Management.Automation.PSCredential ("dbatoolsTestUser", (ConvertTo-SecureString -String "dummy" -AsPlainText -Force))

            $splatSetPrivilegeLocal = @{
                ComputerName = $env:COMPUTERNAME
                Type         = "ServiceLogon"
                Credential   = $testCredential
                Confirm      = $false
            }
            $null = Set-DbaPrivilege @splatSetPrivilegeLocal

            # A parameter filter only defines the parameters the mocked command was called with; any other
            # name resolves through the scope chain, up to the script scope of the module. So { $null -eq
            # $Credential } passed on its own and failed as soon as an earlier test file of the same process
            # had left a $script:credential in the module. Whether the parameter was bound at all is the
            # question, and that is what $PesterBoundParameters answers.
            Should -Invoke Test-PSRemoting -Times 1 -Exactly -ParameterFilter { -not $PesterBoundParameters.ContainsKey("Credential") }
            Should -Invoke Get-DbaService -Times 1 -Exactly -ParameterFilter { -not $PesterBoundParameters.ContainsKey("Credential") }
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Guards the AfterAll revert: only trust $hadCreateGlobalObjects once we know it was
        # actually captured. If this block throws partway through, $preTestStateCaptured stays
        # $false and AfterAll leaves the machine alone instead of guessing at the prior state.
        $preTestStateCaptured = $false
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $currentSid = ([System.Security.Principal.NTAccount]$currentUser).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $privilegeBefore = Get-DbaPrivilege -ComputerName $env:COMPUTERNAME 3>$null | Where-Object User -eq $currentUser
        $hadCreateGlobalObjects = $privilegeBefore.CreateGlobalObjects -eq $true
        $preTestStateCaptured = $true

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Revert the grant unless the user already held the privilege before the test: strip the
        # SID position-independently (secedit re-sorts the SID list on export) and re-apply.
        # Skip entirely if BeforeAll never confirmed the prior state - reverting on an unknown
        # state risks stripping a privilege the user genuinely held before this test ran.
        if ($preTestStateCaptured -and -not $hadCreateGlobalObjects) {
            $revertTempPath = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
            $revertBaseName = "secpolRevertByDbatoolsci-$(Get-Random)"
            $revertCfg = "$revertTempPath\$revertBaseName.cfg"
            $revertDb = "$revertTempPath\$revertBaseName.sdb"
            $revertJfm = "$revertTempPath\$revertBaseName.jfm"

            try {
                $null = secedit /export /cfg $revertCfg
                if ($LASTEXITCODE -ne 0) {
                    throw "secedit /export failed with exit code $LASTEXITCODE while reverting CreateGlobalObjects for $currentUser"
                }

                $revertContent = Get-Content -Path $revertCfg | ForEach-Object {
                    if ($PSItem -match "^SeCreateGlobalPrivilege") {
                        ($PSItem -replace ("\*" + [regex]::Escape($currentSid) + "(,|$)"), "") -replace ",\s*$", ""
                    } else {
                        $PSItem
                    }
                }

                $splatWriteRevertCfg = @{
                    Path     = $revertCfg
                    Value    = $revertContent
                    Encoding = "Unicode"
                }
                Set-Content @splatWriteRevertCfg

                $null = secedit /configure /cfg $revertCfg /db $revertDb /areas USER_RIGHTS /overwrite /quiet
                if ($LASTEXITCODE -ne 0) {
                    throw "secedit /configure failed with exit code $LASTEXITCODE while reverting CreateGlobalObjects for $currentUser"
                }
            } finally {
                $splatRemoveRevertArtifacts = @{
                    Path        = $revertCfg, $revertDb, $revertJfm
                    Force       = $true
                    ErrorAction = "SilentlyContinue"
                }
                Remove-Item @splatRemoveRevertArtifacts
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Does not leave secedit artifacts behind" {
        It "Writes secedit's working database to temp, not the working directory, and cleans it up" {
            $workingDirectory = (Get-Location).Path
            $artifactTempPath = ([System.IO.Path]::GetTempPath()).TrimEnd("\")

            # Watch temp for the working database secedit creates for /db, so this test proves the
            # file was actually routed to temp during the run, not just absent from cwd afterward.
            $seceditWatcher = New-Object -TypeName System.IO.FileSystemWatcher
            $seceditWatcher.Path = $artifactTempPath
            $seceditWatcher.Filter = "secedit-*.sdb"
            $seceditWatcher.EnableRaisingEvents = $true
            $seceditWatcherSourceId = "SetDbaPrivilegeSeceditDbCreated-$(Get-Random)"
            $splatRegisterSeceditWatcher = @{
                InputObject      = $seceditWatcher
                EventName        = "Created"
                SourceIdentifier = $seceditWatcherSourceId
            }
            $null = Register-ObjectEvent @splatRegisterSeceditWatcher

            try {
                $splatGrantCreateGlobalObjects = @{
                    ComputerName    = $env:COMPUTERNAME
                    Type            = "CreateGlobalObjects"
                    User            = $currentUser
                    Confirm         = $false
                    EnableException = $true
                }
                $null = Set-DbaPrivilege @splatGrantCreateGlobalObjects

                # FileSystemWatcher delivers Created events on a background thread and queues them
                # asynchronously, so even though Set-DbaPrivilege above has already returned, the event
                # may not have reached the PowerShell event queue yet - wait for it instead of polling once.
                $seceditDbCreatedEvent = Wait-Event -SourceIdentifier $seceditWatcherSourceId -Timeout 10
                $seceditDbCreatedEvent | Should -Not -BeNullOrEmpty -Because "secedit's /db database should be created under $artifactTempPath while Set-DbaPrivilege runs"

                # Track the exact file(s) the watcher actually saw created, instead of re-scanning temp
                # with the same wildcard afterward - a re-scan can't tell this invocation's artifact
                # apart from a leftover or a concurrent Set-DbaPrivilege run against the same computer.
                $observedSeceditDbPaths = (Get-Event -SourceIdentifier $seceditWatcherSourceId).SourceEventArgs.FullPath | Select-Object -Unique
                $observedSeceditDbPaths | Should -Not -BeNullOrEmpty -Because "the watcher event should carry the created database's path"

                foreach ($observedSeceditDbPath in $observedSeceditDbPaths) {
                    $observedSeceditJfmPath = [System.IO.Path]::ChangeExtension($observedSeceditDbPath, "jfm")
                    Test-Path -Path $observedSeceditDbPath | Should -BeFalse -Because "$observedSeceditDbPath should have been cleaned up after Set-DbaPrivilege ran"
                    Test-Path -Path $observedSeceditJfmPath | Should -BeFalse -Because "$observedSeceditJfmPath should have been cleaned up after Set-DbaPrivilege ran"
                }

                # Legacy regression guard: earlier versions of Set-DbaPrivilege wrote a hardcoded
                # secedit.sdb/secedit.jfm pair (no per-run token) straight into the working directory.
                $splatCheckWorkingDirectoryArtifacts = @{
                    Path        = $workingDirectory
                    Include     = "secedit-*.sdb", "secedit-*.jfm", "secedit.sdb", "secedit.jfm"
                    ErrorAction = "SilentlyContinue"
                }
                Get-ChildItem @splatCheckWorkingDirectoryArtifacts | Should -BeNullOrEmpty
            } finally {
                Unregister-Event -SourceIdentifier $seceditWatcherSourceId -ErrorAction SilentlyContinue
                Remove-Event -SourceIdentifier $seceditWatcherSourceId -ErrorAction SilentlyContinue
                $seceditWatcher.Dispose()
            }
        }
    }

    Context "Local accounts" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Returns the entries of one right from the local security policy, the way secedit exports them:
            # *SID for most accounts, the bare name for local accounts.
            function Get-TestRightEntry {
                param ([string]$Privilege)
                $exportFile = "$([System.IO.Path]::GetTempPath())dbatoolsci_rights_$(Get-Random).cfg"
                try {
                    $null = secedit /export /cfg $exportFile /areas USER_RIGHTS
                    $line = Get-Content -Path $exportFile | Where-Object { $PSItem -match "^$Privilege\s*=" }
                    if ($line) {
                        $line.Split("=", 2)[1].Split(",") | ForEach-Object { $PSItem.Trim() } | Where-Object { $PSItem }
                    }
                } finally {
                    Remove-Item -Path $exportFile -ErrorAction SilentlyContinue
                }
            }

            # Removes the test account from the given rights, by its name and by its SID.
            function Remove-TestRightHolder {
                param (
                    [string[]]$Privilege,
                    [string]$UserName,
                    [string]$Sid
                )
                $baseName = "$([System.IO.Path]::GetTempPath())dbatoolsci_revoke_$(Get-Random)"
                try {
                    $null = secedit /export /cfg "$baseName.cfg" /areas USER_RIGHTS
                    $content = Get-Content -Path "$baseName.cfg" | ForEach-Object {
                        $rightName = $PSItem.Split("=", 2)[0].Trim()
                        if ($rightName -in $Privilege) {
                            $kept = $PSItem.Split("=", 2)[1].Split(",") | ForEach-Object { $PSItem.Trim() } | Where-Object { $PSItem -and $PSItem -ne $UserName -and $PSItem -ne "*$Sid" }
                            "$rightName = $($kept -join ",")"
                        } else {
                            $PSItem
                        }
                    }
                    Set-Content -Path "$baseName.cfg" -Value $content -Encoding Unicode
                    $null = secedit /configure /cfg "$baseName.cfg" /db "$baseName.sdb" /areas USER_RIGHTS /overwrite /quiet
                } finally {
                    Remove-Item -Path "$baseName.cfg", "$baseName.sdb", "$baseName.jfm" -ErrorAction SilentlyContinue
                }
            }

            # Local account names are limited to 20 characters.
            $localUserName = "dbatoolsci_sp$(Get-Random -Maximum 99999)"
            $splatLocalUser = @{
                Name     = $localUserName
                Password = (ConvertTo-SecureString -String "dbatools.IO!$(Get-Random)" -AsPlainText -Force)
            }
            $null = New-LocalUser @splatLocalUser
            $localUserSid = ([System.Security.Principal.NTAccount]"$env:COMPUTERNAME\$localUserName").Translate([System.Security.Principal.SecurityIdentifier]).Value
            $dotAccount = ".\$localUserName"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            Remove-TestRightHolder -Privilege SeLockMemoryPrivilege, SeServiceLogonRight -UserName $localUserName -Sid $localUserSid
            Remove-LocalUser -Name $localUserName -ErrorAction SilentlyContinue
        }

        It "Grants the privilege to a local account named as .\Name" {
            # NTAccount cannot translate .\Name, so the account got no SID and the line an empty * entry.
            $null = Set-DbaPrivilege -Type LPIM -User $dotAccount -Confirm:$false

            $WarnVar | Should -BeNullOrEmpty
            Get-TestRightEntry -Privilege SeLockMemoryPrivilege | Where-Object { $PSItem -eq $localUserName -or $PSItem -eq "*$localUserSid" } | Should -Not -BeNullOrEmpty
        }

        It "Lists an account only once when it is granted again" {
            $null = Set-DbaPrivilege -Type LPIM -User $dotAccount -Confirm:$false

            @(Get-TestRightEntry -Privilege SeLockMemoryPrivilege | Where-Object { $PSItem -eq $localUserName -or $PSItem -eq "*$localUserSid" }) | Should -HaveCount 1
        }

        It "Grants the privilege to a discovered service account named as .\Name" {
            # Windows stores a local service account as .\Name and Get-DbaService returns it unchanged.
            # Only the service lookup is replaced, the local security policy is changed for real.
            $mockService = [scriptblock]::Create(@"
[PSCustomObject]@{
    ServiceName = "dbatoolsci_noservice"
    StartName   = "$dotAccount"
}
"@)
            Mock -ModuleName dbatools -CommandName Get-DbaService -MockWith $mockService

            $null = Set-DbaPrivilege -Type ServiceLogon -Confirm:$false

            $WarnVar | Should -BeNullOrEmpty
            Get-TestRightEntry -Privilege SeServiceLogonRight | Where-Object { $PSItem -eq $localUserName -or $PSItem -eq "*$localUserSid" } | Should -Not -BeNullOrEmpty
        }

        It "Warns and changes nothing for an account that does not exist" {
            $holdersBefore = @(Get-TestRightEntry -Privilege SeLockMemoryPrivilege)

            $null = Set-DbaPrivilege -Type LPIM -User "dbatoolsci_nosuchuser_$(Get-Random)" -Confirm:$false -WarningAction SilentlyContinue

            $WarnVar | Should -BeLike "*Cannot resolve dbatoolsci_nosuchuser_*"
            @(Get-TestRightEntry -Privilege SeLockMemoryPrivilege) | Should -Be $holdersBefore
        }
    }
}
