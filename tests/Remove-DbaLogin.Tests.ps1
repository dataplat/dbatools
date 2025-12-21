#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaLogin",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Login",
                "InputObject",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables for test login creation and cleanup
        $testLogin = "dbatoolsci_removelogin"
        $testPassword = "MyV3ry`$ecur3P@ssw0rd"
        $securePassword = ConvertTo-SecureString $testPassword -AsPlainText -Force

        # Create test login for removal testing
        $splatLogin = @{
            SqlInstance = $TestConfig.instance1
            Login       = $testLogin
            Password    = $securePassword
        }
        $newLogin = New-DbaLogin @splatLogin

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any remaining test login
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login $testLogin -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing a login" {
        It "Should successfully remove the login" {
            $results = Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login $testLogin
            $results.Status | Should -Be "Dropped"

            # Verify the login was actually removed
            $verifyLogin = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login $testLogin
            $verifyLogin | Should -BeNullOrEmpty
        }
    }

    Context "Regression test for issue #9163 - Warn when login not found" {
        It "Should warn when specified login does not exist" {
            $result = Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login "nonexistentlogin" -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warn | Should -Not -BeNullOrEmpty
            $warn | Should -BeLike "*nonexistentlogin*not found*"
        }

        It "Should warn for each non-existent login when multiple are specified" {
            $result = Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login "nonexistent1", "nonexistent2" -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 2
            $warn[0] | Should -BeLike "*nonexistent1*not found*"
            $warn[1] | Should -BeLike "*nonexistent2*not found*"
        }

        It "Should not warn when login exists" {
            # Create a test login first
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $tempLogin = "dbatoolsci_temptest"
            $tempPassword = ConvertTo-SecureString "MyV3ry`$ecur3P@ssw0rd" -AsPlainText -Force
            $null = New-DbaLogin -SqlInstance $TestConfig.instance1 -Login $tempLogin -Password $tempPassword
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # Now try to remove it and check for warnings
            $result = Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login $tempLogin -WarningVariable warn -WarningAction SilentlyContinue
            $result.Status | Should -Be "Dropped"
            $warn | Should -BeNullOrEmpty
        }
    }
}