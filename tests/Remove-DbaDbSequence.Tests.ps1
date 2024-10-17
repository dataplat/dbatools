param($ModuleName = 'dbatools')

Describe "Remove-DbaDbSequence" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbSequence
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have Sequence as a parameter" {
            $CommandUnderTest | Should -HaveParameter Sequence -Type String[] -Not -Mandatory
        }
        It "Should have Schema as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type String[] -Not -Mandatory
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Sequence[] -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            $random = Get-Random
            $server = Connect-DbaInstance -SqlInstance $env:instance2
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
