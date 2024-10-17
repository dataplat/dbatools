param($ModuleName = 'dbatools')

Describe "Test-DbaAgSpn" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaAgSpn
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Credential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have AvailabilityGroup parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type String[] -Mandatory:$false
        }
        It "Should have Listener parameter" {
            $CommandUnderTest | Should -HaveParameter Listener -Type String[] -Mandatory:$false
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type AvailabilityGroup[] -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
        It "Should have Verbose parameter" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type Switch -Mandatory:$false
        }
        It "Should have Debug parameter" {
            $CommandUnderTest | Should -HaveParameter Debug -Type Switch -Mandatory:$false
        }
        It "Should have ErrorAction parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type System.Management.Automation.ActionPreference -Mandatory:$false
        }
        It "Should have WarningAction parameter" {
            $CommandUnderTest | Should -HaveParameter WarningAction -Type System.Management.Automation.ActionPreference -Mandatory:$false
        }
        It "Should have InformationAction parameter" {
            $CommandUnderTest | Should -HaveParameter InformationAction -Type System.Management.Automation.ActionPreference -Mandatory:$false
        }
        It "Should have ProgressAction parameter" {
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type System.Management.Automation.ActionPreference -Mandatory:$false
        }
        It "Should have ErrorVariable parameter" {
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Mandatory:$false
        }
        It "Should have WarningVariable parameter" {
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Mandatory:$false
        }
        It "Should have InformationVariable parameter" {
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Mandatory:$false
        }
        It "Should have OutVariable parameter" {
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Mandatory:$false
        }
        It "Should have OutBuffer parameter" {
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Mandatory:$false
        }
        It "Should have PipelineVariable parameter" {
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Mandatory:$false
        }
    }

    # Add more contexts and tests as needed for the specific functionality of Test-DbaAgSpn
}
