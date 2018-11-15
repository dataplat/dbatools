$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 7
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\New-DbaDacProfile).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Path', 'ConnectionString', 'PublishOptions', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_publishprofile"
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $null = $server.Query("Create Database [$dbname]")
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
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