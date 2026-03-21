#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaWindowsLogin",
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
                "ExcludeLogin",
                "FilterBy",
                "IgnoreDomains",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
Did not include these tests yet as I was unsure if AppVeyor was capable of testing domain logins. Included these for future use.
Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $results = Test-DbaWindowsLogin -SqlInstance $TestConfig.InstanceSingle
        }

        It "Should return correct properties" {
            $expectedProps = @(
                "AccountNotDelegated",
                "AllowReversiblePasswordEncryption",
                "CannotChangePassword",
                "DisabledInSQLServer",
                "Domain",
                "Enabled",
                "Found",
                "LockedOut",
                "Login",
                "PasswordExpired",
                "PasswordNeverExpires",
                "PasswordNotRequired",
                "Server",
                "SmartcardLogonRequired",
                "TrustedForDelegation",
                "Type",
                "UserAccountControl"
            )
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Should return true if Account type is User" {
            $userAccounts = $results | Where-Object Type -match "User"
            $userAccounts | Should -BeTrue
        }

        It "Should return true if Account is Found" {
            $foundAccounts = $results | Where-Object Found
            $foundAccounts.Found | Should -BeTrue
        }
    }
}#>