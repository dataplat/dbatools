param($ModuleName = 'dbatools')

Describe "Get-DbaAgBackupHistory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgBackupHistory
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have AvailabilityGroup as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type String -Not -Mandatory
        }
        It "Should have Database as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type String[] -Not -Mandatory
        }
        It "Should have IncludeCopyOnly as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeCopyOnly -Type Switch -Not -Mandatory
        }
        It "Should have Force as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Not -Mandatory
        }
        It "Should have Since as a non-mandatory parameter of type DateTime" {
            $CommandUnderTest | Should -HaveParameter Since -Type DateTime -Not -Mandatory
        }
        It "Should have RecoveryFork as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter RecoveryFork -Type String -Not -Mandatory
        }
        It "Should have Last as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Last -Type Switch -Not -Mandatory
        }
        It "Should have LastFull as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter LastFull -Type Switch -Not -Mandatory
        }
        It "Should have LastDiff as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter LastDiff -Type Switch -Not -Mandatory
        }
        It "Should have LastLog as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter LastLog -Type Switch -Not -Mandatory
        }
        It "Should have DeviceType as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter DeviceType -Type String[] -Not -Mandatory
        }
        It "Should have Raw as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Raw -Type Switch -Not -Mandatory
        }
        It "Should have LastLsn as a non-mandatory parameter of type BigInteger" {
            $CommandUnderTest | Should -HaveParameter LastLsn -Type BigInteger -Not -Mandatory
        }
        It "Should have IncludeMirror as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeMirror -Type Switch -Not -Mandatory
        }
        It "Should have Type as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Type -Type String[] -Not -Mandatory
        }
        It "Should have LsnSort as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter LsnSort -Type String -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }
}

# No Integration Tests, because we don't have an availability group running in AppVeyor
