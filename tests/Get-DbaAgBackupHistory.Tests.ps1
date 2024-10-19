param($ModuleName = 'dbatools')

Describe "Get-DbaAgBackupHistory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgBackupHistory
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have AvailabilityGroup as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup
        }
        It "Should have Database as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have IncludeCopyOnly as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeCopyOnly
        }
        It "Should have Force as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have Since as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Since
        }
        It "Should have RecoveryFork as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter RecoveryFork
        }
        It "Should have Last as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Last
        }
        It "Should have LastFull as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter LastFull
        }
        It "Should have LastDiff as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter LastDiff
        }
        It "Should have LastLog as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter LastLog
        }
        It "Should have DeviceType as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter DeviceType
        }
        It "Should have Raw as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Raw
        }
        It "Should have LastLsn as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter LastLsn
        }
        It "Should have IncludeMirror as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeMirror
        }
        It "Should have Type as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have LsnSort as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter LsnSort
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

# No Integration Tests, because we don't have an availability group running in AppVeyor
