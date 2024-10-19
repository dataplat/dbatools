param($ModuleName = 'dbatools')

Describe "Get-DbaRgClassifierFunction" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaRgClassifierFunction
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
