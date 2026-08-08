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

                if ($ArgumentList.Count -gt 0) {
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

    Context "Does not leave secedit artifacts behind" {
        It "Does not create secedit.sdb or secedit.jfm in the working directory" {
            $workingDirectory = (Get-Location).Path

            $splatSetPrivilege = @{
                ComputerName = $env:COMPUTERNAME
                Type         = "CreateGlobalObjects"
                User         = $currentUser
                Confirm      = $false
            }
            $null = Set-DbaPrivilege @splatSetPrivilege 3>$null

            Join-Path -Path $workingDirectory -ChildPath "secedit.sdb" | Should -Not -Exist
            Join-Path -Path $workingDirectory -ChildPath "secedit.jfm" | Should -Not -Exist
        }

        It "Does not leave secedit.sdb or secedit.jfm behind in the temp directory either" {
            $tempPath = ([System.IO.Path]::GetTempPath()).TrimEnd("\")

            Join-Path -Path $tempPath -ChildPath "secedit.sdb" | Should -Not -Exist
            Join-Path -Path $tempPath -ChildPath "secedit.jfm" | Should -Not -Exist
        }
    }
}
