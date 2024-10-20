param($ModuleName = 'dbatools')

Describe "Remove-DbaDbSequence" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbSequence
        }

        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Sequence",
                "Schema",
                "InputObject",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $random = Get-Random
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $newDbName = "dbatoolsci_newdb_$random"
            $null = New-DbaDatabase -SqlInstance $server -Name $newDbName

            $null = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random"
            $null = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence2_$random" -Schema "Schema_$random"
        }

        AfterAll {
            $null = Remove-DbaDatabase -Confirm:$false -SqlInstance $server -Database $newDbName
        }

        It "removes a sequence" {
            $sequence = Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random"
            $sequence | Should -Not -BeNullOrEmpty
            Remove-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random" -Confirm:$false
            $removedSequence = Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random"
            $removedSequence | Should -BeNullOrEmpty
        }

        It "supports piping sequences" {
            $sequence = Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence2_$random" -Schema "Schema_$random"
            $sequence | Should -Not -BeNullOrEmpty
            $sequence | Remove-DbaDbSequence -Confirm:$false
            $removedSequence = Get-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence2_$random" -Schema "Schema_$random"
            $removedSequence | Should -BeNullOrEmpty
        }
    }
}
