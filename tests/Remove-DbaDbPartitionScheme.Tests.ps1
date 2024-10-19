param($ModuleName = 'dbatools')

Describe "Remove-DbaDbPartitionScheme" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbPartitionScheme
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have WhatIf parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf
        }
        It "Should have Confirm parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm
        }
    }
}

Describe "Remove-DbaDbPartitionScheme Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $dbname2 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $server -Name $dbname1
        $null = New-DbaDatabase -SqlInstance $server -Name $dbname2

        $partfun1 = "dbatoolssci_partfun1_$(Get-Random)"
        $partfun2 = "dbatoolssci_partfun2_$(Get-Random)"
        $partsch1 = "dbatoolssci_partsch1_$(Get-Random)"
        $partsch2 = "dbatoolssci_partsch2_$(Get-Random)"
        $null = $server.Query("CREATE PARTITION FUNCTION $partfun1 (int) AS RANGE LEFT FOR VALUES (1, 100, 1000); CREATE PARTITION SCHEME $partsch1 AS PARTITION $partfun1 ALL TO ( [PRIMARY] );", $dbname1)
        $null = $server.Query("CREATE PARTITION FUNCTION $partfun2 (int) AS RANGE LEFT FOR VALUES (1, 100, 1000); CREATE PARTITION SCHEME $partsch2 AS PARTITION $partfun2 ALL TO ( [PRIMARY] );", $dbname2)
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname1, $dbname2 -Confirm:$false
    }

    Context "commands work as expected" {
        It "removes partition scheme" {
            Get-DbaDbPartitionScheme -SqlInstance $server -Database $dbname1 | Should -Not -BeNullOrEmpty
            Remove-DbaDbPartitionScheme -SqlInstance $server -Database $dbname1 -Confirm:$false
            Get-DbaDbPartitionScheme -SqlInstance $server -Database $dbname1 | Should -BeNullOrEmpty
        }

        It "supports piping partition scheme" {
            Get-DbaDbPartitionScheme -SqlInstance $server -Database $dbname2 | Should -Not -BeNullOrEmpty
            Get-DbaDbPartitionScheme -SqlInstance $server -Database $dbname2 | Remove-DbaDbPartitionScheme -Confirm:$false
            Get-DbaDbPartitionScheme -SqlInstance $server -Database $dbname2 | Should -BeNullOrEmpty
        }
    }
}
