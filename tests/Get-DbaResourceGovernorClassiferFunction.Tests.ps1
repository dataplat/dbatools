$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $sql = "CREATE FUNCTION dbatoolsci_fnRG()
                RETURNS sysname
                WITH SCHEMABINDING
                AS
                BEGIN
                     RETURN N'gOffHoursProcessing'
                END"

        Invoke-DbaSqlQuery -SqlInstance $script:instance2 -Query $sql
        Invoke-DbaSqlQuery -SqlInstance $script:instance2 -Query "ALTER RESOURCE GOVERNOR with (CLASSIFIER_FUNCTION = dbo.dbatoolsci_fnRG); ALTER RESOURCE GOVERNOR RECONFIGURE"
    }
    AfterAll {
        Invoke-DbaSqlQuery -SqlInstance $script:instance2 -Query "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL); ALTER RESOURCE GOVERNOR RECONFIGURE"
        Invoke-DbaSqlQuery -SqlInstance $script:instance2 -Query "DROP FUNCTION [dbo].[dbatoolsci_fnRG]"
    }

    Context "Command works" {
        It "returns the proper classifier function" {
            $results = Get-DbaResourceGovernorClassiferFunction -SqlInstance $script:instance2
            $results.Name | Should -Be 'dbatoolsci_fnRG'
        }
    }
}