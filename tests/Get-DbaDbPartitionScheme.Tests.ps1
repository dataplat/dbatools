#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbPartitionScheme",
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
                "PartitionScheme",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Set variables. They are available in all the It blocks.
        $tempguid = [guid]::newguid()
        $PFName = "dbatoolssci_$($tempguid.guid)"
        $PFScheme = "dbatoolssci_PFScheme"

        # Create the test partition scheme
        $CreateTestPartitionScheme = @"
CREATE PARTITION FUNCTION [$PFName] (int)  AS RANGE LEFT FOR VALUES (1, 100, 1000, 10000, 100000);
GO
CREATE PARTITION SCHEME $PFScheme AS PARTITION [$PFName] ALL TO ( [PRIMARY] );
"@

        $splatCreate = @{
            SqlInstance = $TestConfig.instance2
            Query       = $CreateTestPartitionScheme
            Database    = "master"
        }
        Invoke-DbaQuery @splatCreate

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created objects.
        $DropTestPartitionScheme = @"
DROP PARTITION SCHEME [$PFScheme];
GO
DROP PARTITION FUNCTION [$PFName];
"@
        $splatDrop = @{
            SqlInstance     = $TestConfig.instance2
            Query           = $DropTestPartitionScheme
            Database        = "master"
            EnableException = $true
        }
        Invoke-DbaQuery @splatDrop -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Partition Schemes are correctly located" {
        BeforeAll {
            $results1 = Get-DbaDbPartitionScheme -SqlInstance $TestConfig.instance2 -Database master | Select-Object *
            $results2 = Get-DbaDbPartitionScheme -SqlInstance $TestConfig.instance2
        }

        It "Should execute and return results" {
            $results2 | Should -Not -Be $null
        }

        It "Should execute against Master and return results" {
            $results1 | Should -Not -Be $null
        }

        It "Should have matching name $PFScheme" {
            $results1.name | Should -Be $PFScheme
        }

        It "Should have PartitionFunction of $PFName " {
            $results1.PartitionFunction | Should -Be $PFName
        }

        It "Should have FileGroups of [Primary]" {
            $results1.FileGroups | Should -Be @("PRIMARY", "PRIMARY", "PRIMARY", "PRIMARY", "PRIMARY", "PRIMARY")
        }

        It "Should not Throw an Error" {
            { Get-DbaDbPartitionScheme -SqlInstance $TestConfig.instance2 -ExcludeDatabase master } | Should -Not -Throw
        }
    }
}