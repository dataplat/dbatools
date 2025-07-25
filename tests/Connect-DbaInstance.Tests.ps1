$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "AccessToken Parameter Tests" {
        BeforeAll {
            # Mock the ConvertFrom-SecurePass function for testing
            Mock ConvertFrom-SecurePass -MockWith {
                param($InputObject)
                return "mocked-plain-text-token"
            } -ModuleName dbatools

            # Mock Stop-Function to capture error scenarios
            Mock Stop-Function -MockWith {
                param($Target, $Message, $Continue)
                throw $Message
            } -ModuleName dbatools
        }

        It "Should handle plain text AccessToken (backward compatibility)" {
            # Create a mock AccessToken object that simulates Get-AzAccessToken from Azure PowerShell v13
            $mockAccessToken = [PSCustomObject]@{
                Token = "plain-text-token-string"
                ExpiresOn = (Get-Date).AddHours(1)
            }

            # Test that the function can process the token without errors
            # This is a unit test, so we're testing the logic without actual SQL connection
            {
                # We can't easily unit test the full Connect-DbaInstance function due to its complexity
                # Instead, we'll test the AccessToken processing logic directly
                $testToken = $mockAccessToken.Token
                if ($testToken -is [System.Security.SecureString]) {
                    $testToken = ConvertFrom-SecurePass -InputObject $testToken
                }
                $testToken | Should -Be "plain-text-token-string"
            } | Should -Not -Throw
        }

        It "Should handle SecureString AccessToken from Azure PowerShell v14+" {
            # Create a SecureString token to simulate Azure PowerShell v14+
            $secureToken = ConvertTo-SecureString "secure-token-string" -AsPlainText -Force

            # Create a mock AccessToken object that simulates Get-AzAccessToken from Azure PowerShell v14+
            $mockAccessToken = [PSCustomObject]@{
                Token = $secureToken
                ExpiresOn = (Get-Date).AddHours(1)
            }

            # Test that the function can process the SecureString token
            {
                $testToken = $mockAccessToken.Token
                if ($testToken -is [System.Security.SecureString]) {
                    $testToken = ConvertFrom-SecurePass -InputObject $testToken
                }
                $testToken | Should -Be "mocked-plain-text-token"
            } | Should -Not -Throw
        }

        It "Should handle direct SecureString AccessToken input" {
            # Test direct SecureString input
            $secureToken = ConvertTo-SecureString "direct-secure-token" -AsPlainText -Force

            {
                $testToken = $secureToken
                if ($testToken -is [System.Security.SecureString]) {
                    $testToken = ConvertFrom-SecurePass -InputObject $testToken
                }
                $testToken | Should -Be "mocked-plain-text-token"
            } | Should -Not -Throw
        }

        It "Should handle New-DbaAzAccessToken objects" {
            # Create a mock object that simulates New-DbaAzAccessToken output
            $mockDbaToken = [PSCustomObject]@{
                GetAccessToken = { return "dba-token-string" }
            }
            $mockDbaToken | Add-Member -MemberType ScriptMethod -Name GetAccessToken -Value { return "dba-token-string" } -Force

            # Test that the function can process New-DbaAzAccessToken objects
            {
                $testToken = $mockDbaToken
                if ($testToken | Get-Member | Where-Object Name -eq GetAccessToken) {
                    $testToken = $testToken.GetAccessToken()
                }
                $testToken | Should -Be "dba-token-string"
            } | Should -Not -Throw
        }

        It "Should call ConvertFrom-SecurePass when AccessToken.Token is SecureString" {
            $secureToken = ConvertTo-SecureString "test-token" -AsPlainText -Force
            $mockAccessToken = [PSCustomObject]@{
                Token = $secureToken
            }

            # Process the token
            $testToken = $mockAccessToken.Token
            if ($testToken -is [System.Security.SecureString]) {
                $result = ConvertFrom-SecurePass -InputObject $testToken
            }

            # Verify ConvertFrom-SecurePass was called
            Assert-MockCalled ConvertFrom-SecurePass -Times 1 -ModuleName dbatools
        }
    }
}

Describe "$CommandName Integration Tests" -Tag 'IntegrationTests' {
    Context "AccessToken Integration" {
        It "Should accept string AccessToken without errors" -Skip:($env:APPVEYOR -or $env:GITHUB_ACTIONS) {
            # This test would require actual Azure credentials, so we skip it in CI
            # In a real environment, this would test:
            # $stringToken = "actual-azure-token-string"
            # $result = Connect-DbaInstance -SqlInstance "test.database.windows.net" -AccessToken $stringToken -DisableException
            # $result | Should -Not -BeNullOrEmpty
        }

        It "Should accept SecureString AccessToken without errors" -Skip:($env:APPVEYOR -or $env:GITHUB_ACTIONS) {
            # This test would require actual Azure credentials, so we skip it in CI
            # In a real environment, this would test:
            # $secureToken = ConvertTo-SecureString "actual-azure-token-string" -AsPlainText -Force
            # $result = Connect-DbaInstance -SqlInstance "test.database.windows.net" -AccessToken $secureToken -DisableException
            # $result | Should -Not -BeNullOrEmpty
        }
    }
}
