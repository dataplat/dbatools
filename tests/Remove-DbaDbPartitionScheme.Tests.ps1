#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbPartitionScheme",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
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

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname1, $dbname2

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Commands work as expected" {
        It "removes partition scheme" {
            Get-DbaDbPartitionScheme -SqlInstance $server -Database $dbname1 | Should -Not -BeNullOrEmpty
            Remove-DbaDbPartitionScheme -SqlInstance $server -Database $dbname1
            Get-DbaDbPartitionScheme -SqlInstance $server -Database $dbname1 | Should -BeNullOrEmpty
        }

        It "supports piping partition scheme" {
            Get-DbaDbPartitionScheme -SqlInstance $server -Database $dbname2 | Should -Not -BeNullOrEmpty
            Get-DbaDbPartitionScheme -SqlInstance $server -Database $dbname2 | Remove-DbaDbPartitionScheme
            Get-DbaDbPartitionScheme -SqlInstance $server -Database $dbname2 | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputDbName = "dbatoolsci_outval_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $server -Name $outputDbName -EnableException
            $outputPartFun = "dbatoolssci_outpf_$(Get-Random)"
            $outputPartSch = "dbatoolssci_outps_$(Get-Random)"
            $null = $server.Query("CREATE PARTITION FUNCTION $outputPartFun (int) AS RANGE LEFT FOR VALUES (1, 100, 1000); CREATE PARTITION SCHEME $outputPartSch AS PARTITION $outputPartFun ALL TO ( [PRIMARY] );", $outputDbName)
            $result = Get-DbaDbPartitionScheme -SqlInstance $server -Database $outputDbName | Remove-DbaDbPartitionScheme -Confirm:$false
        }

        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $server -Database $outputDbName -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "PartitionSchemeName",
                "Status",
                "IsRemoved"
            )
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }

        It "Has correct values for a successful removal" {
            $result[0].Status | Should -Be "Dropped"
            $result[0].IsRemoved | Should -BeTrue
            $result[0].Database | Should -Be $outputDbName
            $result[0].PartitionSchemeName | Should -Be $outputPartSch
        }
    }
}