$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Since', 'Object', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing if schema changes are discovered" {
        BeforeAll {
            $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
            $db.Query("CREATE TABLE dbatoolsci_schemachange (id int identity)")
            $db.Query("EXEC sp_rename 'dbatoolsci_schemachange', 'dbatoolsci_schemachange1'")
        }
        AfterAll {
            $db.Query("DROP TABLE dbo.dbatoolsci_schemachange1")
        }

        $results = Get-DbaSchemaChangeHistory -SqlInstance $script:instance1 -Database tempdb

        It "notices dbatoolsci_schemachange changed" {
            $results.Object -match 'dbatoolsci_schemachange' | Should Be $true
        }
    }
}