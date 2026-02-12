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

Describe $CommandName -Tag IntegrationTests -Skip:($env:appveyor) {
    Context "Output validation" -Skip:(-not $TestConfig.InstanceSingle) {
        BeforeAll {
            $result = Test-DbaWindowsLogin -SqlInstance $TestConfig.InstanceSingle
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no Windows domain logins found to validate" }
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected default display properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no Windows domain logins found to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "Server",
                "Domain",
                "Login",
                "Type",
                "Found",
                "SamAccountNameMismatch",
                "DisabledInSQLServer",
                "Enabled",
                "LockedOut",
                "PasswordExpired",
                "PasswordNotRequired"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the expected excluded properties still accessible" {
            if (-not $result) { Set-ItResult -Skipped -Because "no Windows domain logins found to validate" }
            $excludedProps = @(
                "AccountNotDelegated",
                "AllowReversiblePasswordEncryption",
                "CannotChangePassword",
                "PasswordNeverExpires",
                "SmartcardLogonRequired",
                "TrustedForDelegation",
                "UserAccountControl"
            )
            foreach ($prop in $excludedProps) {
                $result[0].psobject.Properties.Name | Should -Contain $prop -Because "excluded property '$prop' should still be accessible"
            }
        }

        It "Should not have excluded properties in the default display set" {
            if (-not $result) { Set-ItResult -Skipped -Because "no Windows domain logins found to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $excludedProps = @(
                "AccountNotDelegated",
                "AllowReversiblePasswordEncryption",
                "CannotChangePassword",
                "PasswordNeverExpires",
                "SmartcardLogonRequired",
                "TrustedForDelegation",
                "UserAccountControl"
            )
            foreach ($prop in $excludedProps) {
                $defaultProps | Should -Not -Contain $prop -Because "property '$prop' should be excluded from the default display set"
            }
        }
    }
}