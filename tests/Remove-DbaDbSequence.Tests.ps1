#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbSequence",
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
                "Sequence",
                "Schema",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $newDbName = "dbatoolsci_newdb_$random"
        $null = New-DbaDatabase -SqlInstance $server -Name $newDbName

        $null = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random"
        $null = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence2_$random" -Schema "Schema_$random"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $server -Database $newDbName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Commands work as expected" {
        It "Removes a sequence" {
            (Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random") | Should -Not -BeNullOrEmpty
            Remove-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random"
            (Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random") | Should -BeNullOrEmpty
        }

        It "Supports piping sequences" {
            (Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence2_$random" -Schema "Schema_$random") | Should -Not -BeNullOrEmpty
            $script:result = Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence2_$random" -Schema "Schema_$random" | Remove-DbaDbSequence
            (Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence2_$random" -Schema "Schema_$random") | Should -BeNullOrEmpty
        }

        Context "Output validation" {
            It "Returns output of the documented type" {
                $script:result | Should -Not -BeNullOrEmpty
                $script:result | Should -BeOfType [PSCustomObject]
            }

            It "Has the expected output properties" {
                $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Sequence", "SequenceName", "SequenceSchema", "Status", "IsRemoved")
                foreach ($prop in $expectedProps) {
                    $script:result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
                }
            }

            It "Has the correct values for status properties" {
                $script:result[0].Status | Should -Be "Dropped"
                $script:result[0].IsRemoved | Should -BeTrue
            }
        }
    }
}