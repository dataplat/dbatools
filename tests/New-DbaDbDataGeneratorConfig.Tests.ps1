$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'ResetIdentity', 'TruncateTable', 'Rows', 'Path', 'Force', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_generatorconfig"
        $sql = "CREATE TABLE [dbo].[people](
                    [FirstName] [varchar](50) NULL,
                    [LastName] [varchar](50) NULL,
                    [City] [datetime] NULL
                ) ON [PRIMARY]"
        $db = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbname
        $db.Query($sql)
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
        $results | Remove-Item -Confirm:$false -ErrorAction Ignore
    }

    Context "Command works" {

        It "Should output a file with specific content" {
            $results = New-DbaDbDataGeneratorConfig -SqlInstance $script:instance1 -Database $dbname -Path C:\temp
            $results.Directory.Name | Should -Be temp

            $results.FullName | Should -FileContentMatch $dbname

            $results.FullName | Should -FileContentMatch FirstName
        }
    }
}