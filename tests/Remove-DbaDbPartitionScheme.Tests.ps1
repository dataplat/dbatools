param($ModuleName = 'dbatools')

Describe "Remove-DbaDbPartitionScheme" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbPartitionScheme
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type PartitionScheme[] -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
        It "Should have Verbose parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch -Not -Mandatory
        }
        It "Should have Debug parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch -Not -Mandatory
        }
        It "Should have ErrorAction parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have WarningAction parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have InformationAction parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ProgressAction parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
        }
        It "Should have ErrorVariable parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Not -Mandatory
        }
        It "Should have WarningVariable parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Not -Mandatory
        }
        It "Should have InformationVariable parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Not -Mandatory
        }
        It "Should have OutVariable parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Not -Mandatory
        }
        It "Should have OutBuffer parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Not -Mandatory
        }
        It "Should have PipelineVariable parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Not -Mandatory
        }
        It "Should have WhatIf parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf -Type Switch -Not -Mandatory
        }
        It "Should have Confirm parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm -Type Switch -Not -Mandatory
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
