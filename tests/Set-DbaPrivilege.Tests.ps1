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
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
