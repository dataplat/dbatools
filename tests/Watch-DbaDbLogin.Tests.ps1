param($ModuleName = 'dbatools')

Describe "Watch-DbaDbLogin" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Watch-DbaDbLogin
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have Table as a parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type String
        }
        It "Should have SqlCms as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCms -Type String
        }
        It "Should have ServersFromFile as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServersFromFile -Type String
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Server[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $random = Get-Random

            $tableName1 = 'dbatoolsciwatchdblogin1'
            $tableName2 = 'dbatoolsciwatchdblogin2'
            $tableName3 = 'dbatoolsciwatchdblogin3'
            $databaseName = "dbatoolsci_$random"
            $newDb = New-DbaDatabase -SqlInstance $env:instance1 -Name $databaseName

            $testFile = 'C:\temp\Servers_$random.txt'
            if (Test-Path $testFile) {
                Remove-Item $testFile -Force
            }

            $env:instance1, $env:instance2 | Out-File $testFile

            $server1 = Connect-DbaInstance -SqlInstance $env:instance1
            $server2 = Connect-DbaInstance -SqlInstance $env:instance2

            $regServer1 = Add-DbaRegServer -SqlInstance $env:instance1 -ServerName $env:instance1 -Name "dbatoolsci_instance1_$random"
            $regServer2 = Add-DbaRegServer -SqlInstance $env:instance1 -ServerName $env:instance2 -Name "dbatoolsci_instance2_$random"
        }

        AfterAll {
            $null = $newDb | Remove-DbaDatabase -Confirm:$false
            Get-DbaRegServer -SqlInstance $env:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        }

        It "ServersFromFile" {
            Watch-DbaDbLogin -SqlInstance $env:instance1 -Database $databaseName -Table $tableName1 -ServersFromFile $testFile -EnableException
            $result = Get-DbaDbTable -SqlInstance $env:instance1 -Database $databaseName -Table $tableName1 -IncludeSystemDBs
            $result.Name | Should -Be $tableName1
            $result.Count | Should -BeGreaterThan 0
        }

        It "Pipeline of instances" {
            $server1, $server2 | Watch-DbaDbLogin -SqlInstance $env:instance1 -Database $databaseName -Table $tableName2 -EnableException
            $result = Get-DbaDbTable -SqlInstance $env:instance1 -Database $databaseName -Table $tableName2 -IncludeSystemDBs
            $result.Name | Should -Be $tableName2
            $result.Count | Should -BeGreaterThan 0
        }

        It "ServersFromCMS" {
            Watch-DbaDbLogin -SqlInstance $env:instance1 -Database $databaseName -Table $tableName3 -SqlCms $env:instance1 -EnableException
            $result = Get-DbaDbTable -SqlInstance $env:instance1 -Database $databaseName -Table $tableName3 -IncludeSystemDBs
            $result.Name | Should -Be $tableName3
            $result.Count | Should -BeGreaterThan 0
        }
    }
}
