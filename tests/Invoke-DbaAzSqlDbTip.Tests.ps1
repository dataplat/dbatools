$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'AzureDomain', 'Tenant', 'LocalFile', 'Database', 'ExcludeDatabase', 'AllUserDatabases', 'ReturnAllTips', 'Compat100', 'StatementTimeout', 'EnableException', 'Force'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandName Integration Tests" -Tags "IntegrationTests" {
    if ($env:azuredbpasswd -eq "failstoooften") {
        Context "Run the tips against Azure database" {
            $securePassword = ConvertTo-SecureString $env:azuredbpasswd -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential ($TestConfig.azuresqldblogin, $securePassword)

            $results = Invoke-DbaAzSqlDbTip -SqlInstance $TestConfig.azureserver -Database test -SqlCredential $cred -ReturnAllTips

            It "Should get some results" {
                $results | Should -not -BeNullOrEmpty
            }

            It "Should have the right ComputerName" {
                $results.ComputerName | Should -Be $TestConfig.azureserver
            }

            It "Database name should be 'test'" {
                $results.Database | Should -Be 'test'
            }
        }
    }
}
