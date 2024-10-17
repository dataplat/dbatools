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
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Login parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String[] -Mandatory:$false
        }
        It "Should have ExcludeLogin parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeLogin -Type String[] -Mandatory:$false
        }
        It "Should have FilterBy parameter" {
            $CommandUnderTest | Should -HaveParameter FilterBy -Type String -Mandatory:$false
        }
        It "Should have IgnoreDomains parameter" {
            $CommandUnderTest | Should -HaveParameter IgnoreDomains -Type String[] -Mandatory:$false
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Login[] -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
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
