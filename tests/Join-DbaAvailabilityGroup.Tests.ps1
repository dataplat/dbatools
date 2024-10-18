param($ModuleName = 'dbatools')

Describe "Join-DbaAvailabilityGroup" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Join-DbaAvailabilityGroup
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have AvailabilityGroup as a parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type System.String[]
        }
        It "Should have ClusterType as a parameter" {
            $CommandUnderTest | Should -HaveParameter ClusterType -Type System.String
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    # Add more contexts and tests as needed for Join-DbaAvailabilityGroup
    # For example:
    # Context "Joining an Availability Group" {
    #     BeforeAll {
    #         # Setup code for this context
    #     }
    #     It "Successfully joins the Availability Group" {
    #         # Test code
    #     }
    #     AfterAll {
    #         # Cleanup code for this context
    #     }
    # }
}
