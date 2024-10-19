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
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "AzureDomain",
                "Tenant",
                "LocalFile",
                "Database",
                "ExcludeDatabase",
                "AllUserDatabases",
                "ReturnAllTips",
                "Compat100",
                "StatementTimeout",
                "EnableException",
                "Force"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
