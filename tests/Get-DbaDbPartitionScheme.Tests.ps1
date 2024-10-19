param($ModuleName = 'dbatools')

Describe "Get-DbaDbPartitionScheme" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbPartitionScheme
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have PartitionScheme as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter PartitionScheme
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Get-DbaDbPartitionScheme Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . (Join-Path $PSScriptRoot 'constants.ps1')
    }

    BeforeAll {
        $tempguid = [guid]::newguid();
        $PFName = "dbatoolssci_$($tempguid.guid)"
        $PFScheme = "dbatoolssci_PFScheme"

        $CreateTestPartitionScheme = @"
CREATE PARTITION FUNCTION [$PFName] (int)  AS RANGE LEFT FOR VALUES (1, 100, 1000, 10000, 100000);
GO
CREATE PARTITION SCHEME $PFScheme AS PARTITION [$PFName] ALL TO ( [PRIMARY] );
"@

        Invoke-DbaQuery -SqlInstance $global:instance2 -Query $CreateTestPartitionScheme -Database master
    }

    AfterAll {
        $DropTestPartitionScheme = @"
DROP PARTITION SCHEME [$PFScheme];
GO
DROP PARTITION FUNCTION [$PFName];
"@
        Invoke-DbaQuery -SqlInstance $global:instance2 -Query $DropTestPartitionScheme -Database master
    }

    Context "Partition Schemes are correctly located" {
        It "Should execute and return results" {
            $results2 = Get-DbaDbPartitionScheme -SqlInstance $global:instance2
            $results2 | Should -Not -BeNullOrEmpty
        }

        It "Should execute against Master and return results" {
            $results1 = Get-DbaDbPartitionScheme -SqlInstance $global:instance2 -Database master
            $results1 | Should -Not -BeNullOrEmpty
        }

        It "Should have matching name $PFScheme" {
            $results1 = Get-DbaDbPartitionScheme -SqlInstance $global:instance2 -Database master
            $results1.name | Should -Be $PFScheme
        }

        It "Should have PartitionFunction of $PFName" {
            $results1 = Get-DbaDbPartitionScheme -SqlInstance $global:instance2 -Database master
            $results1.PartitionFunction | Should -Be $PFName
        }

        It "Should have FileGroups of [Primary]" {
            $results1 = Get-DbaDbPartitionScheme -SqlInstance $global:instance2 -Database master
            $results1.FileGroups | Should -Be @('PRIMARY', 'PRIMARY', 'PRIMARY', 'PRIMARY', 'PRIMARY', 'PRIMARY')
        }

        It "Should not Throw an Error when excluding master database" {
            { Get-DbaDbPartitionScheme -SqlInstance $global:instance2 -ExcludeDatabase master } | Should -Not -Throw
        }
    }
}
