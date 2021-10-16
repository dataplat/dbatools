$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'InputObject', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $sql = "CREATE FUNCTION dbatoolsci_fnRG()
                RETURNS sysname
                WITH SCHEMABINDING
                AS
                BEGIN
                     RETURN N'gOffHoursProcessing'
                END"

        Invoke-DbaQuery -SqlInstance $script:instance2 -Query $sql
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query "ALTER RESOURCE GOVERNOR with (CLASSIFIER_FUNCTION = dbo.dbatoolsci_fnRG); ALTER RESOURCE GOVERNOR RECONFIGURE"
    }
    AfterAll {
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query "ALTER RESOURCE GOVERNOR WITH (CLASSIFIER_FUNCTION = NULL); ALTER RESOURCE GOVERNOR RECONFIGURE"
        Invoke-DbaQuery -SqlInstance $script:instance2 -Query "DROP FUNCTION [dbo].[dbatoolsci_fnRG]"
    }

    Context "Command works" {
        It "returns the proper classifier function" {
            $results = Get-DbaRgClassifierFunction -SqlInstance $script:instance2
            $results.Name | Should -Be 'dbatoolsci_fnRG'
        }
    }
}