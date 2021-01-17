$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Path', 'ConnectionString', 'PublishOptions', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_publishprofile"
        $db = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbname
        $null = $db.Query("CREATE TABLE dbo.example (id int);
            INSERT dbo.example
            SELECT top 100 1
            FROM sys.objects")
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
    }

    It "returns the right results" {
        $publishprofile = New-DbaDacProfile -SqlInstance $script:instance1 -Database $dbname
        $publishprofile.FileName -match 'publish.xml' | Should Be $true
        Remove-Item -Confirm:$false -Path $publishprofile.FileName -ErrorAction SilentlyContinue
    }
}