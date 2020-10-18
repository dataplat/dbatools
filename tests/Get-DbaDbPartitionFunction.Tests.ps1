$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $tempguid = [guid]::newguid();
        $PFName = "dbatoolssci_$($tempguid.guid)"
        $CreateTestPartitionFunction = "CREATE PARTITION FUNCTION [$PFName] (int)  AS RANGE LEFT FOR VALUES (1, 100, 1000, 10000, 100000);"
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query $CreateTestPartitionFunction -Database master
    }
    AfterAll {
        $DropTestPartitionFunction = "DROP PARTITION FUNCTION [$PFName];"
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query $DropTestPartitionFunction -Database master
    }

    Context "Partition Functions are correctly located" {
        $results1 = Get-DbaDbPartitionFunction -SqlInstance $script:instance2 -Database master | Select-Object *
        $results2 = Get-DbaDbPartitionFunction -SqlInstance $script:instance2

        It "Should execute and return results" {
            $results2 | Should -Not -Be $null
        }

        It "Should execute against Master and return results" {
            $results1 | Should -Not -Be $null
        }

        It "Should have matching name $PFName" {
            $results1.name | Should -Be $PFName
        }

        It "Should have range values of @(1, 100, 1000, 10000, 100000)" {
            $results1.rangeValues | Should -Be @(1, 100, 1000, 10000, 100000)
        }

        It "Should have PartitionFunctionParameters of Int" {
            $results1.PartitionFunctionParameters | Should -Be "[int]"
        }

        It "Should not Throw an Error" {
            {Get-DbaDbPartitionFunction -SqlInstance $script:instance2 -ExcludeDatabase master } | Should -not -Throw
        }
    }
}