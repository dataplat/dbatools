param($ModuleName = 'dbatools')

Describe "Get-DbaDbPartitionFunction" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbPartitionFunction
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "PartitionFunction",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Partition Functions are correctly located" {
        BeforeAll {
            $tempguid = [guid]::newguid();
            $PFName = "dbatoolssci_$($tempguid.guid)"
            $CreateTestPartitionFunction = "CREATE PARTITION FUNCTION [$PFName] (int)  AS RANGE LEFT FOR VALUES (1, 100, 1000, 10000, 100000);"
            Invoke-DbaQuery -SqlInstance $global:instance2 -Query $CreateTestPartitionFunction -Database master
        }
        AfterAll {
            $DropTestPartitionFunction = "DROP PARTITION FUNCTION [$PFName];"
            Invoke-DbaQuery -SqlInstance $global:instance2 -Query $DropTestPartitionFunction -Database master
        }

        It "Should execute and return results" {
            $results2 = Get-DbaDbPartitionFunction -SqlInstance $global:instance2
            $results2 | Should -Not -BeNullOrEmpty
        }

        It "Should execute against Master and return results" {
            $results1 = Get-DbaDbPartitionFunction -SqlInstance $global:instance2 -Database master | Select-Object *
            $results1 | Should -Not -BeNullOrEmpty
        }

        It "Should have matching name $PFName" {
            $results1 = Get-DbaDbPartitionFunction -SqlInstance $global:instance2 -Database master | Select-Object *
            $results1.name | Should -Be $PFName
        }

        It "Should have range values of @(1, 100, 1000, 10000, 100000)" {
            $results1 = Get-DbaDbPartitionFunction -SqlInstance $global:instance2 -Database master | Select-Object *
            $results1.rangeValues | Should -Be @(1, 100, 1000, 10000, 100000)
        }

        It "Should have PartitionFunctionParameters of Int" {
            $results1 = Get-DbaDbPartitionFunction -SqlInstance $global:instance2 -Database master | Select-Object *
            $results1.PartitionFunctionParameters | Should -Be "[int]"
        }

        It "Should not Throw an Error when excluding master database" {
            { Get-DbaDbPartitionFunction -SqlInstance $global:instance2 -ExcludeDatabase master } | Should -Not -Throw
        }
    }
}
