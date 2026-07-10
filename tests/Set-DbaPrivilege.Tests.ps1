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

Describe "$CommandName regressions" -Tag UnitTests {
    # These exercise the command's policy-file editing WITHOUT touching the real local security
    # policy: a GLOBAL secedit function shadows secedit.exe for the localhost in-process execution
    # path (PowerShell resolves commands through the dynamic scope chain, so the shim is visible to
    # the scriptblocks the command runs in-process on localhost regardless of whether the command
    # is the PS function or the compiled cmdlet). The shim fakes the export by writing a canned
    # policy file and captures the file content at /configure time - so no real privilege is ever
    # changed; each test asserts the shim's /configure capture to prove the editing ran.
    BeforeEach {
        $script:policyFile = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "secpolByDbatools.cfg"
        $global:dbatoolsTestPolicyContent = $null

        function global:secedit {
            param(
                [Parameter(ValueFromRemainingArguments)]
                [object[]]$ArgumentList
            )
            $argText = "$ArgumentList"
            if ($argText -match "/export") {
                $cfgIndex = [array]::IndexOf($ArgumentList, "/cfg") + 1
                Set-Content -Path $ArgumentList[$cfgIndex] -Value @(
                    "[Privilege Rights]"
                    "SeCreateGlobalPrivilege = "
                )
            }
            if ($argText -match "/configure") {
                $global:dbatoolsTestPolicyContent = Get-Content -Path (Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "secpolByDbatools.cfg")
            }
        }
    }

    AfterEach {
        Remove-Item -Path Function:\secedit -ErrorAction SilentlyContinue
        Remove-Item -Path $script:policyFile -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name dbatoolsTestPolicyContent -Scope Global -ErrorAction SilentlyContinue
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

        $global:dbatoolsTestPolicyContent | Should -Not -BeNullOrEmpty
        ($global:dbatoolsTestPolicyContent | Where-Object { $PSItem -match "^SeCreateGlobalPrivilege" }) |
            Should -Match "^SeCreateGlobalPrivilege = \*$([regex]::Escape($expectedSid))(,)?$"
    }
}

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
        # Revert the grant unless the user already held the privilege before the test: strip the
        # SID position-independently (secedit re-sorts the SID list on export) and re-apply.
        if (-not $hadCreateGlobalObjects) {
            $tempPath = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
            $revertCfg = "$tempPath\secpolRevertByDbatoolsci.cfg"
            $null = secedit /export /cfg $revertCfg
            $revertContent = Get-Content -Path $revertCfg | ForEach-Object {
                if ($PSItem -match "^SeCreateGlobalPrivilege") {
                    ($PSItem -replace ("\*" + [regex]::Escape($currentSid) + ",?"), "") -replace ",\s*$", ""
                } else {
                    $PSItem
                }
            }
            Set-Content -Path $revertCfg -Value $revertContent -Encoding Unicode
            $null = secedit /configure /cfg $revertCfg /db "$tempPath\secpolRevertByDbatoolsci.sdb" /areas USER_RIGHTS /overwrite /quiet
            Remove-Item -Path $revertCfg, "$tempPath\secpolRevertByDbatoolsci.sdb" -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Grants CreateGlobalObjects to a specific user on localhost" {
        It "Runs the grant without warnings" {
            $splatSetPrivilege = @{
                ComputerName    = $env:COMPUTERNAME
                Type            = "CreateGlobalObjects"
                User            = $currentUser
                Confirm         = $false
                WarningVariable = "warnGrant"
            }
            $null = Set-DbaPrivilege @splatSetPrivilege 3>$null
            $warnGrant | Should -BeNullOrEmpty
        }

        It "Makes the privilege visible to Get-DbaPrivilege" {
            $privilegeAfter = Get-DbaPrivilege -ComputerName $env:COMPUTERNAME 3>$null | Where-Object User -eq $currentUser
            $privilegeAfter.CreateGlobalObjects | Should -BeTrue
        }

        It "Is idempotent on a second run" {
            $splatSetPrivilege = @{
                ComputerName    = $env:COMPUTERNAME
                Type            = "CreateGlobalObjects"
                User            = $currentUser
                Confirm         = $false
                WarningVariable = "warnRepeat"
            }
            $null = Set-DbaPrivilege @splatSetPrivilege 3>$null
            $warnRepeat | Should -BeNullOrEmpty
            $privilegeStill = Get-DbaPrivilege -ComputerName $env:COMPUTERNAME 3>$null | Where-Object User -eq $currentUser
            $privilegeStill.CreateGlobalObjects | Should -BeTrue
        }
    }
}
