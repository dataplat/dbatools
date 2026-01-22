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
            (Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle).Name | Should -Contain $tablename
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

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $dbname -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Table]
        }

        It "Has the expected base default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'Schema',
                'Name',
                'IndexSpaceUsed',
                'DataSpaceUsed',
                'RowCount',
                'HasClusteredIndex',
                'FullTextIndex'
            )
            $actualProps = $result[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has dbatools-added properties" {
            $result[0].PSObject.Properties.Name | Should -Contain 'ComputerName' -Because "dbatools adds ComputerName"
            $result[0].PSObject.Properties.Name | Should -Contain 'InstanceName' -Because "dbatools adds InstanceName"
            $result[0].PSObject.Properties.Name | Should -Contain 'SqlInstance' -Because "dbatools adds SqlInstance"
            $result[0].PSObject.Properties.Name | Should -Contain 'Database' -Because "dbatools adds Database"
        }

        It "Has version-specific properties when supported" {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
            $actualProps = $result[0].PSObject.Properties.Name

            if ($server.VersionMajor -ge 9) {
                $actualProps | Should -Contain 'IsPartitioned' -Because "SQL Server 2005+ should have IsPartitioned"
            }
            if ($server.VersionMajor -ge 10) {
                $actualProps | Should -Contain 'ChangeTrackingEnabled' -Because "SQL Server 2008+ should have ChangeTrackingEnabled"
            }
            if ($server.VersionMajor -ge 11) {
                $actualProps | Should -Contain 'IsFileTable' -Because "SQL Server 2012+ should have IsFileTable"
            }
            if ($server.VersionMajor -ge 12) {
                $actualProps | Should -Contain 'IsMemoryOptimized' -Because "SQL Server 2014+ should have IsMemoryOptimized"
            }
            if ($server.VersionMajor -ge 14) {
                $actualProps | Should -Contain 'IsNode' -Because "SQL Server 2017+ should have IsNode"
                $actualProps | Should -Contain 'IsEdge' -Because "SQL Server 2017+ should have IsEdge"
            }
        }
    }
}