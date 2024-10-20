param($ModuleName = 'dbatools')

Describe "Test-DbaWindowsLogin" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaWindowsLogin
        }
        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Login",
            "ExcludeLogin",
            "FilterBy",
            "IgnoreDomains",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        BeforeDiscovery {
            $env:skipIntegrationTests = [Environment]::GetEnvironmentVariable('DBA_TOOLS_SKIP_INTEGRATION_TESTS') -eq 'true'
        }

        It "Should return correct properties" -Skip:$env:skipIntegrationTests {
            $results = Test-DbaWindowsLogin -SqlInstance $global:instance2
            $ExpectedProps = 'AccountNotDelegated', 'AllowReversiblePasswordEncryption', 'CannotChangePassword', 'DisabledInSQLServer', 'Domain', 'Enabled', 'Found', 'LockedOut', 'Login', 'PasswordExpired', 'PasswordNeverExpires', 'PasswordNotRequired', 'Server', 'SmartcardLogonRequired', 'TrustedForDelegation', 'Type', 'UserAccountControl'
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should return true if Account type is User" -Skip:$env:skipIntegrationTests {
            $results = Test-DbaWindowsLogin -SqlInstance $global:instance2
            ($results | Where-Object Type -match 'User').Count | Should -BeGreaterThan 0
        }

        It "Should return true if Account is Found" -Skip:$env:skipIntegrationTests {
            $results = Test-DbaWindowsLogin -SqlInstance $global:instance2
            ($results | Where-Object Found).Found | Should -Be $true
        }
    }
}
