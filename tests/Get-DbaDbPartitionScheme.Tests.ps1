$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'PartitionScheme', 'EnableException'
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
        $PFScheme = "dbatoolssci_PFScheme"

        $CreateTestPartitionScheme = @"
CREATE PARTITION FUNCTION [$PFName] (int)  AS RANGE LEFT FOR VALUES (1, 100, 1000, 10000, 100000);
GO
CREATE PARTITION SCHEME $PFScheme AS PARTITION [$PFName] ALL TO ( [PRIMARY] );
"@

        Invoke-DbaQuery -SqlInstance $server -Query $CreateTestPartitionScheme -Database master
        Invoke-DbaQuery -SqlInstance $server -Query $CreateTestPartitionScheme -Database model
    }
    AfterAll {
        $DropTestPartitionScheme = @"
DROP PARTITION SCHEME [$PFScheme];
GO
DROP PARTITION FUNCTION [$PFName];
"@
        Invoke-DbaQuery -SqlInstance $server -Query $DropTestPartitionScheme -Database master
        Invoke-DbaQuery -SqlInstance $server -Query $DropTestPartitionScheme -Database model
    }

    Context "Partition Schemes are correctly located" {
        $results1 = Get-DbaDbPartitionScheme -SqlInstance $server -Database master | Select-Object *
        $results2 = Get-DbaDbPartitionScheme -SqlInstance $server

        It "Should execute and return results" {
            $results2 | Should -Not -Be $null
        }

        It "Should execute against Master and return results" {
            $results1 | Should -Not -Be $null
        }

        It "Should have matching name $PFScheme" {
            $results1[0].name | Should -Be $PFScheme
        }

        It "finds a sequence on an instance by name only" {
            $partSch = Get-DbaDbPartitionScheme -SqlInstance $server -PartitionScheme $PFScheme
            $partSch.Name | Select-Object -Unique | Should -Be $PFScheme
            $partSch.Count | Should -Be 2
        }

        It "Should have PartitionFunction of $PFName " {
            $results1[0].PartitionFunction | Should -Be $PFName
        }

        It "Should have FileGroups of [Primary]" {
            $results1[0].FileGroups | Should -Be @('PRIMARY', 'PRIMARY', 'PRIMARY', 'PRIMARY', 'PRIMARY', 'PRIMARY')
        }

        It "Should not Throw an Error" {
            {Get-DbaDbPartitionScheme -SqlInstance $server -ExcludeDatabase master } | Should -not -Throw
        }
    }
}