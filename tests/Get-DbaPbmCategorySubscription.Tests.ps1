param($ModuleName = 'dbatools')

Describe "Get-DbaPbmCategorySubscription" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPbmCategorySubscription
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type System.Management.Automation.PSObject[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type System.Management.Automation.PSObject[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Mandatory:$false
        }
    }

    # Add more contexts here for additional tests
    # For example:
    # Context "Command Execution" {
    #     BeforeAll {
    #         # Setup code, if needed
    #     }
    #     It "Should return expected results" {
    #         # Test code
    #     }
    # }
}
