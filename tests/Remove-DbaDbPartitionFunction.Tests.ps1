param($ModuleName = 'dbatools')

Describe "Remove-DbaDbPartitionFunction" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbPartitionFunction
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $dbname1 = "dbatoolsci_$(Get-Random)"
            $dbname2 = "dbatoolsci_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $server -Name $dbname1
            $null = New-DbaDatabase -SqlInstance $server -Name $dbname2

            $partfun1 = "dbatoolssci_partfun1_$(Get-Random)"
            $partfun2 = "dbatoolssci_partfun2_$(Get-Random)"
            $null = $server.Query("CREATE PARTITION FUNCTION $partfun1 (int) AS RANGE LEFT FOR VALUES (1, 100, 1000);", $dbname1)
            $null = $server.Query("CREATE PARTITION FUNCTION $partfun2 (int) AS RANGE LEFT FOR VALUES (1, 100, 1000);", $dbname2)
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname1, $dbname2 -Confirm:$false
        }

        It "removes partition function" {
            Get-DbaDbPartitionFunction -SqlInstance $server -Database $dbname1 | Should -Not -BeNullOrEmpty
            Remove-DbaDbPartitionFunction -SqlInstance $server -Database $dbname1 -Confirm:$false
            Get-DbaDbPartitionFunction -SqlInstance $server -Database $dbname1 | Should -BeNullOrEmpty
        }

        It "supports piping partition function" {
            Get-DbaDbPartitionFunction -SqlInstance $server -Database $dbname2 | Should -Not -BeNullOrEmpty
            Get-DbaDbPartitionFunction -SqlInstance $server -Database $dbname2 | Remove-DbaDbPartitionFunction -Confirm:$false
            Get-DbaDbPartitionFunction -SqlInstance $server -Database $dbname2 | Should -BeNullOrEmpty
        }
    }
}
