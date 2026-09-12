#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaPrivilege",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

InModuleScope dbatools {
    Describe "Get-DbaPrivilege regressions" -Tag UnitTests {
        BeforeEach {
            Mock Test-PSRemoting { $true }
            Mock Invoke-Command2 {
                [PSCustomObject]@{
                    BatchLogon                = @("CONTOSO\svc")
                    InstantFileInitialization = @()
                    LockPagesInMemory         = @()
                    GenerateSecurityAudit     = @()
                    LogonAsAService           = @()
                    CreateGlobalObjects       = @()
                }
            }
        }

        It "passes the credential to the remoting connectivity test" {
            # Regression test: the credential was not passed to Test-PSRemoting, so the pre-flight
            # check authenticated with the implicit identity and failed although the credential
            # would have worked - for example when the caller itself runs in a remoting session
            # with a network logon token (double hop).
            $testCredential = New-Object System.Management.Automation.PSCredential ("dbatoolsTestUser", (ConvertTo-SecureString -String "dummy" -AsPlainText -Force))

            $null = Get-DbaPrivilege -ComputerName dbatoolsTestRemote -Credential $testCredential

            Should -Invoke Test-PSRemoting -Times 1 -Exactly -ParameterFilter { $Credential -eq $testCredential }
        }

        It "does not pass the credential to the connectivity test for the local computer" {
            # Invoke-Command2 runs locally under the process identity and ignores -Credential, so
            # the pre-flight has to do the same - a credential that is valid remotely but not
            # locally must not reject the local computer of a mixed list.
            $testCredential = New-Object System.Management.Automation.PSCredential ("dbatoolsTestUser", (ConvertTo-SecureString -String "dummy" -AsPlainText -Force))

            $null = Get-DbaPrivilege -ComputerName $env:COMPUTERNAME -Credential $testCredential

            Should -Invoke Test-PSRemoting -Times 1 -Exactly -ParameterFilter { $null -eq $Credential }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Gets Instance Privilege" {
        BeforeAll {
            $results = Get-DbaPrivilege -ComputerName $env:ComputerName -WarningVariable warn 3> $null
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should not warn" {
            $warn | Should -BeNullOrEmpty
        }
    }
}