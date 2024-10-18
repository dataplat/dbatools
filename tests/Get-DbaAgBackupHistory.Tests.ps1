param($ModuleName = 'dbatools')

Describe "Get-DbaAgBackupHistory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgBackupHistory
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type Microsoft.SqlServer.Management.Smo.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type Microsoft.SqlServer.Management.Smo.PSCredential -Mandatory:$false
        }
        It "Should have AvailabilityGroup as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type System.String -Mandatory:$false
        }
        It "Should have Database as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.String[] -Mandatory:$false
        }
        It "Should have IncludeCopyOnly as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeCopyOnly -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have Force as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have Since as a non-mandatory parameter of type System.DateTime" {
            $CommandUnderTest | Should -HaveParameter Since -Type System.DateTime -Mandatory:$false
        }
        It "Should have RecoveryFork as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter RecoveryFork -Type System.String -Mandatory:$false
        }
        It "Should have Last as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Last -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have LastFull as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter LastFull -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have LastDiff as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter LastDiff -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have LastLog as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter LastLog -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have DeviceType as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter DeviceType -Type System.String[] -Mandatory:$false
        }
        It "Should have Raw as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Raw -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have LastLsn as a non-mandatory parameter of type System.Int64" {
            $CommandUnderTest | Should -HaveParameter LastLsn -Type System.Int64 -Mandatory:$false
        }
        It "Should have IncludeMirror as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeMirror -Type System.Management.Automation.Switch -Mandatory:$false
        }
        It "Should have Type as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Type -Type System.String[] -Mandatory:$false
        }
        It "Should have LsnSort as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter LsnSort -Type System.String -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.Switch -Mandatory:$false
        }
    }
}

# No Integration Tests, because we don't have an availability group running in AppVeyor
