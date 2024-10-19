param($ModuleName = 'dbatools')

Describe "Invoke-DbaAzSqlDbTip" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaAzSqlDbTip
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have AzureDomain as a parameter" {
            $CommandUnderTest | Should -HaveParameter AzureDomain
        }
        It "Should have Tenant as a parameter" {
            $CommandUnderTest | Should -HaveParameter Tenant
        }
        It "Should have LocalFile as a parameter" {
            $CommandUnderTest | Should -HaveParameter LocalFile
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have AllUserDatabases as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllUserDatabases
        }
        It "Should have ReturnAllTips as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ReturnAllTips
        }
        It "Should have Compat100 as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Compat100
        }
        It "Should have StatementTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter StatementTimeout
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
    }

    Context "Run the tips against Azure database" {
        BeforeDiscovery {
            $env:skipAzureTests = [Environment]::GetEnvironmentVariable('azuredbpasswd') -ne "failstoooften"
        }

        BeforeAll {
            $securePassword = ConvertTo-SecureString $env:azuredbpasswd -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ($env:azuresqldblogin, $securePassword)
            $results = Invoke-DbaAzSqlDbTip -SqlInstance $env:azureserver -Database test -SqlCredential $cred -ReturnAllTips
        }

        It "Should get some results" -Skip:$env:skipAzureTests {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have the right ComputerName" -Skip:$env:skipAzureTests {
            $results.ComputerName | Should -Be $env:azureserver
        }

        It "Database name should be 'test'" -Skip:$env:skipAzureTests {
            $results.Database | Should -Be 'test'
        }
    }
}
