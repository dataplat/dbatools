param($ModuleName = 'dbatools')

Describe "Get-DbaRgClassifierFunction" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRgClassifierFunction
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type ResourceGovernor[] -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command works" {
        BeforeAll {
            $sql = "CREATE FUNCTION dbatoolsci_fnRG()
                    RETURNS sysname
                    WITH SCHEMABINDING
                    AS
                    BEGIN
                         RETURN N'gOffHoursProcessing'
                    END"

            Invoke-DbaQuery -SqlInstance $env:instance2 -Query $sql
            Invoke-DbaQuery -SqlInstance $env:instance2 -Query "ALTER RESOURCE GOVERNOR with (CLASSIFIER_FUNCTION = dbo.dbatoolsci_fnRG); ALTER RESOURCE GOVERNOR RECONFIGURE"
        }
        AfterAll {
            Invoke-DbaQuery -SqlInstance $env:instance2 -Query "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL); ALTER RESOURCE GOVERNOR RECONFIGURE"
            Invoke-DbaQuery -SqlInstance $env:instance2 -Query "DROP FUNCTION [dbo].[dbatoolsci_fnRG]"
        }

        It "returns the proper classifier function" {
            $results = Get-DbaRgClassifierFunction -SqlInstance $env:instance2
            $results.Name | Should -Be 'dbatoolsci_fnRG'
        }
    }
}
