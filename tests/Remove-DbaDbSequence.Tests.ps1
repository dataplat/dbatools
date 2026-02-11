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
            Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence2_$random" -Schema "Schema_$random" | Remove-DbaDbSequence
            (Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence2_$random" -Schema "Schema_$random") | Should -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $null = New-DbaDbSequence -SqlInstance $TestConfig.InstanceSingle -Database $newDbName -Sequence "dbatoolsci_OutputSeq_$random" -Schema "Schema_$random"
            $result = Get-DbaDbSequence -SqlInstance $TestConfig.InstanceSingle -Database $newDbName -Sequence "dbatoolsci_OutputSeq_$random" -Schema "Schema_$random" | Remove-DbaDbSequence -Confirm:$false
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected output properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Sequence", "SequenceName", "SequenceSchema", "Status", "IsRemoved")
            foreach ($prop in $expectedProps) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Has the correct values for status properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].Status | Should -Be "Dropped"
            $result[0].IsRemoved | Should -BeTrue
        }
    }
}