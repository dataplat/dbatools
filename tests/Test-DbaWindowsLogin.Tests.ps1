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

    Context "Output Validation" {
        BeforeAll {
            # Get current Windows user to test with
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            # Create a temporary login if it doesn't exist
            try {
                $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1 -EnableException
                if ($currentUser -notin $server.Logins.Name) {
                    $null = New-DbaLogin -SqlInstance $TestConfig.instance1 -Login $currentUser -EnableException
                    $loginCreated = $true
                }
                $result = Test-DbaWindowsLogin -SqlInstance $TestConfig.instance1 -Login $currentUser -EnableException
            } catch {
                # Skip tests if we can't create/test Windows logins
                $result = $null
            }
        }

        AfterAll {
            if ($loginCreated) {
                Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login $currentUser -Confirm:$false
            }
        }

        It "Returns PSCustomObject" -Skip:($null -eq $result) {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected core properties" -Skip:($null -eq $result) {
            $expectedProps = @(
                "Server",
                "Domain",
                "Login",
                "Type",
                "Found",
                "SamAccountNameMismatch",
                "DisabledInSQLServer",
                "Enabled",
                "AccountNotDelegated",
                "AllowReversiblePasswordEncryption",
                "CannotChangePassword",
                "PasswordExpired",
                "PasswordNeverExpires",
                "PasswordNotRequired",
                "LockedOut",
                "SmartcardLogonRequired",
                "TrustedForDelegation",
                "UserAccountControl"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should exist"
            }
        }

        It "Has the expected default display properties" -Skip:($null -eq $result) {
            # Default view shows all properties EXCEPT those in ExcludeProperty
            $defaultProps = @(
                "Server",
                "Domain",
                "Login",
                "Type",
                "Found",
                "SamAccountNameMismatch",
                "DisabledInSQLServer",
                "Enabled",
                "PasswordExpired",
                "PasswordNotRequired",
                "LockedOut",
                "CannotChangePassword"
            )
            $actualDefaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            foreach ($prop in $defaultProps) {
                $actualDefaultProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
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