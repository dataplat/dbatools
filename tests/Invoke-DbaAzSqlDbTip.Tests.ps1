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
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have AzureDomain as a parameter" {
            $CommandUnderTest | Should -HaveParameter AzureDomain -Type String
        }
        It "Should have Tenant as a parameter" {
            $CommandUnderTest | Should -HaveParameter Tenant -Type String
        }
        It "Should have LocalFile as a parameter" {
            $CommandUnderTest | Should -HaveParameter LocalFile -Type String
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[]
        }
        It "Should have AllUserDatabases as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllUserDatabases -Type Switch
        }
        It "Should have ReturnAllTips as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ReturnAllTips -Type Switch
        }
        It "Should have Compat100 as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Compat100 -Type Switch
        }
        It "Should have StatementTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter StatementTimeout -Type Int32
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
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
