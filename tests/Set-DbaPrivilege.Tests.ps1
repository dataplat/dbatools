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
            $script:policyFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "secpolByDbatools.cfg"
            $script:capturedPolicyContent = $null

            Mock Test-ElevationRequirement { $true }
            Mock Test-PSRemoting { $true }
            Mock Invoke-Command2 {
                param(
                    $ComputerName,
                    $Credential,
                    $ScriptBlock,
                    $ArgumentList
                )

                if ($ScriptBlock.ToString() -match "secedit /export /cfg") {
                    Set-Content -Path $script:policyFile -Value @(
                        "[Privilege Rights]"
                        "SeCreateGlobalPrivilege = "
                    )
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

        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $currentSid = ([System.Security.Principal.NTAccount]$currentUser).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $privilegeBefore = Get-DbaPrivilege -ComputerName $env:COMPUTERNAME 3>$null | Where-Object User -eq $currentUser
        $hadCreateGlobalObjects = $privilegeBefore.CreateGlobalObjects -eq $true

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Revert the grant unless the user already held the privilege before the test: strip the
        # SID position-independently (secedit re-sorts the SID list on export) and re-apply.
        if (-not $hadCreateGlobalObjects) {
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
            $null = Register-ObjectEvent -InputObject $seceditWatcher -EventName Created -SourceIdentifier $seceditWatcherSourceId

            try {
                $splatGrantCreateGlobalObjects = @{
                    ComputerName    = $env:COMPUTERNAME
                    Type            = "CreateGlobalObjects"
                    User            = $currentUser
                    Confirm         = $false
                    EnableException = $true
                }
                $null = Set-DbaPrivilege @splatGrantCreateGlobalObjects

                $seceditDbCreatedEvents = Get-Event -SourceIdentifier $seceditWatcherSourceId -ErrorAction SilentlyContinue
                $seceditDbCreatedEvents | Should -Not -BeNullOrEmpty -Because "secedit's /db database should be created under $artifactTempPath while Set-DbaPrivilege runs"

                Get-ChildItem -Path $workingDirectory -Filter "secedit-*.sdb" -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
                Get-ChildItem -Path $workingDirectory -Filter "secedit-*.jfm" -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
                Get-ChildItem -Path $artifactTempPath -Filter "secedit-*.sdb" -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
                Get-ChildItem -Path $artifactTempPath -Filter "secedit-*.jfm" -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            } finally {
                Unregister-Event -SourceIdentifier $seceditWatcherSourceId -ErrorAction SilentlyContinue
                Remove-Event -SourceIdentifier $seceditWatcherSourceId -ErrorAction SilentlyContinue
                $seceditWatcher.Dispose()
            }
        }
    }
}
