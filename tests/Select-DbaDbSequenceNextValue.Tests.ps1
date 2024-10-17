param($ModuleName = 'dbatools')

Describe "Select-DbaDbSequenceNextValue" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Select-DbaDbSequenceNextValue
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have Sequence as a parameter" {
            $CommandUnderTest | Should -HaveParameter Sequence -Type String[]
        }
        It "Should have Schema as a parameter" {
            $CommandUnderTest | Should -HaveParameter Schema -Type String
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Select-DbaDbSequenceNextValue Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $env:instance2
        $newDbName = "dbatoolsci_newdb_$random"
        $newDb = New-DbaDatabase -SqlInstance $server -Name $newDbName

        $sequence = New-DbaDbSequence -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random" -StartWith 100
    }

    AfterAll {
        $null = $newDb | Remove-DbaDatabase -Confirm:$false
    }

    Context "commands work as expected" {
        It "validates required Database param" {
            $sequenceValue = Select-DbaDbSequenceNextValue -SqlInstance $server -Sequence SequenceTest -ErrorVariable error
            $sequenceValue | Should -BeNullOrEmpty
            $error | Should -Match "Database is required when SqlInstance is specified"
        }

        It "selects the next value of a sequence" {
            $sequenceValue = Select-DbaDbSequenceNextValue -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random"
            $sequenceValue | Should -Be 100

            $sequenceValue = Select-DbaDbSequenceNextValue -SqlInstance $server -Database $newDbName -Sequence "Sequence1_$random" -Schema "Schema_$random"
            $sequenceValue | Should -Be 101
        }

        It "supports piping databases" {
            $sequenceValue = Get-DbaDatabase -SqlInstance $server -Database $newDbName | Select-DbaDbSequenceNextValue -Sequence "Sequence1_$random" -Schema "Schema_$random"
            $sequenceValue | Should -Be 102
        }
    }
}
