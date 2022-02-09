$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'PartitionFunction', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $tempguid = [guid]::newguid();
        $PFName = "dbatoolssci_$($tempguid.guid)"
        $CreateTestPartitionFunction = "CREATE PARTITION FUNCTION [$PFName] (int)  AS RANGE LEFT FOR VALUES (1, 100, 1000, 10000, 100000);"
        Invoke-DbaQuery -SqlInstance $server -Query $CreateTestPartitionFunction -Database master
        Invoke-DbaQuery -SqlInstance $server -Query $CreateTestPartitionFunction -Database model
    }
    AfterAll {
        $DropTestPartitionFunction = "DROP PARTITION FUNCTION [$PFName];"
        Invoke-DbaQuery -SqlInstance $server -Query $DropTestPartitionFunction -Database master
        Invoke-DbaQuery -SqlInstance $server -Query $DropTestPartitionFunction -Database model
    }

    Context "Partition Functions are correctly located" {
        $results1 = Get-DbaDbPartitionFunction -SqlInstance $server -Database master | Select-Object *
        $results2 = Get-DbaDbPartitionFunction -SqlInstance $server

        It "Should execute and return results" {
            $results2 | Should -Not -Be $null
        }

        It "Should execute against Master and return results" {
            $results1 | Should -Not -Be $null
        }

        It "Should have matching name $PFName" {
            $results1[0].name | Should -Be $PFName
        }

        It "finds a sequence on an instance by name only" {
            $partFun = Get-DbaDbPartitionFunction -SqlInstance $server -PartitionFunction $PFName
            $partFun.Name | Select-Object -Unique | Should -Be $PFName
            $partFun.Count | Should -Be 2
        }

        It "Should have range values of @(1, 100, 1000, 10000, 100000)" {
            $results1[0].rangeValues | Should -Be @(1, 100, 1000, 10000, 100000)
        }

        It "Should have PartitionFunctionParameters of Int" {
            $results1[0].PartitionFunctionParameters | Should -Be "[int]"
        }

        It "Should not Throw an Error" {
            {Get-DbaDbPartitionFunction -SqlInstance $server -ExcludeDatabase master } | Should -not -Throw
        }
    }
}