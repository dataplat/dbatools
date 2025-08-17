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
            Confirm     = $false
        }
        $newLogin = New-DbaLogin @splatLogin

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any remaining test login
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login $testLogin -Confirm:$false -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When removing a login" {
        It "Should successfully remove the login" {
            $results = Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login $testLogin -Confirm:$false
            $results.Status | Should -Be "Dropped"

            # Verify the login was actually removed
            $verifyLogin = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login $testLogin
            $verifyLogin | Should -BeNullOrEmpty
        }
    }
}