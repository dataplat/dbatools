#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbTable",
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
                "IncludeSystemDBs",
                "Table",
                "EnableException",
                "InputObject",
                "Schema"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbname = "dbatoolsscidb_$(Get-Random)"
        $tablename = "dbatoolssci_$(Get-Random)"

        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname -Owner sa
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Query "Create table $tablename (col1 int)"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Query "drop table $tablename"
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Should get the table" {
        It "Gets the table" {
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -OutVariable "global:dbatoolsciOutput").Name | Should -Contain $tablename
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle).Name | Should -Contain $tablename
        }

        It "Gets the table when you specify the database" {
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $dbname).Name | Should -Contain $tablename
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $dbname).Name | Should -Contain $tablename
        }
    }

    Context "Should not get the table if database is excluded" {
        It "Doesn't find the table" {
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $dbname).Name | Should -Not -Contain $tablename
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $dbname).Name | Should -Not -Contain $tablename
        }
    }

    Context "Output validation" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        }

        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Table]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Schema",
                "Name",
                "IndexSpaceUsed",
                "DataSpaceUsed",
                "RowCount",
                "HasClusteredIndex"
            )
            if ($server.VersionMajor -ge 9) {
                $expectedColumns += "IsPartitioned"
            }
            if ($server.VersionMajor -ge 10) {
                $expectedColumns += "ChangeTrackingEnabled"
            }
            if ($server.VersionMajor -ge 11) {
                $expectedColumns += "IsFileTable"
            }
            if ($server.VersionMajor -ge 12) {
                $expectedColumns += "IsMemoryOptimized"
            }
            if ($server.VersionMajor -ge 14) {
                $expectedColumns += @("IsNode", "IsEdge")
            }
            $expectedColumns += "FullTextIndex"
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Table"
        }
    }
}