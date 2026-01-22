#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbPartitionFunction",
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
                "PartitionFunction",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $tempguid = [guid]::newguid()
        $PFName = "dbatoolssci_$($tempguid.guid)"
        $CreateTestPartitionFunction = "CREATE PARTITION FUNCTION [$PFName] (int) AS RANGE LEFT FOR VALUES (1, 100, 1000, 10000, 100000);"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $CreateTestPartitionFunction -Database master

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $DropTestPartitionFunction = "DROP PARTITION FUNCTION [$PFName];"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query $DropTestPartitionFunction -Database master -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Partition Functions are correctly located" {
        BeforeAll {
            $results1 = Get-DbaDbPartitionFunction -SqlInstance $TestConfig.InstanceSingle -Database master | Select-Object *
            $results2 = Get-DbaDbPartitionFunction -SqlInstance $TestConfig.InstanceSingle
        }

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
            { Get-DbaDbPartitionFunction -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase master } | Should -Not -Throw
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaDbPartitionFunction -SqlInstance $TestConfig.InstanceSingle -Database master -EnableException
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.PartitionFunction]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'CreateDate',
                'Name',
                'NumberOfPartitions'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}