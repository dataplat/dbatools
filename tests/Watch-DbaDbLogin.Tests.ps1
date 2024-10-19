param($ModuleName = 'dbatools')

Describe "Watch-DbaDbLogin" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Watch-DbaDbLogin
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "SqlCms",
                "ServersFromFile",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $random = Get-Random

            $tableName1 = 'dbatoolsciwatchdblogin1'
            $tableName2 = 'dbatoolsciwatchdblogin2'
            $tableName3 = 'dbatoolsciwatchdblogin3'
            $databaseName = "dbatoolsci_$random"
            $newDb = New-DbaDatabase -SqlInstance $global:instance1 -Name $databaseName

            $testFile = 'C:\temp\Servers_$random.txt'
            if (Test-Path $testFile) {
                Remove-Item $testFile -Force
            }

            $global:instance1, $global:instance2 | Out-File $testFile

            $server1 = Connect-DbaInstance -SqlInstance $global:instance1
            $server2 = Connect-DbaInstance -SqlInstance $global:instance2

            $regServer1 = Add-DbaRegServer -SqlInstance $global:instance1 -ServerName $global:instance1 -Name "dbatoolsci_instance1_$random"
            $regServer2 = Add-DbaRegServer -SqlInstance $global:instance1 -ServerName $global:instance2 -Name "dbatoolsci_instance2_$random"
        }

        AfterAll {
            $null = $newDb | Remove-DbaDatabase -Confirm:$false
            Get-DbaRegServer -SqlInstance $global:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        }

        It "ServersFromFile" {
            Watch-DbaDbLogin -SqlInstance $global:instance1 -Database $databaseName -Table $tableName1 -ServersFromFile $testFile -EnableException
            $result = Get-DbaDbTable -SqlInstance $global:instance1 -Database $databaseName -Table $tableName1 -IncludeSystemDBs
            $result.Name | Should -Be $tableName1
            $result.Count | Should -BeGreaterThan 0
        }

        It "Pipeline of instances" {
            $server1, $server2 | Watch-DbaDbLogin -SqlInstance $global:instance1 -Database $databaseName -Table $tableName2 -EnableException
            $result = Get-DbaDbTable -SqlInstance $global:instance1 -Database $databaseName -Table $tableName2 -IncludeSystemDBs
            $result.Name | Should -Be $tableName2
            $result.Count | Should -BeGreaterThan 0
        }

        It "ServersFromCMS" {
            Watch-DbaDbLogin -SqlInstance $global:instance1 -Database $databaseName -Table $tableName3 -SqlCms $global:instance1 -EnableException
            $result = Get-DbaDbTable -SqlInstance $global:instance1 -Database $databaseName -Table $tableName3 -IncludeSystemDBs
            $result.Name | Should -Be $tableName3
            $result.Count | Should -BeGreaterThan 0
        }
    }
}
