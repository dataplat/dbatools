param($ModuleName = 'dbatools')

Describe "Get-DbaRgClassifierFunction" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRgClassifierFunction
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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

            Invoke-DbaQuery -SqlInstance $global:instance2 -Query $sql
            Invoke-DbaQuery -SqlInstance $global:instance2 -Query "ALTER RESOURCE GOVERNOR with (CLASSIFIER_FUNCTION = dbo.dbatoolsci_fnRG); ALTER RESOURCE GOVERNOR RECONFIGURE"
        }
        AfterAll {
            Invoke-DbaQuery -SqlInstance $global:instance2 -Query "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL); ALTER RESOURCE GOVERNOR RECONFIGURE"
            Invoke-DbaQuery -SqlInstance $global:instance2 -Query "DROP FUNCTION [dbo].[dbatoolsci_fnRG]"
        }

        It "returns the proper classifier function" {
            $results = Get-DbaRgClassifierFunction -SqlInstance $global:instance2
            $results.Name | Should -Be 'dbatoolsci_fnRG'
        }
    }
}
