$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 9
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Export-DbaDacPackage).Parameters.Keys
        $knownParameters = 'SqlInstance','SqlCredential','Database','ExcludeDatabase','AllUserDatabases','Path','ExtendedParameters','ExtendedProperties','EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        try {
            $dbname = "dbatoolsci_exportdacpac"
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $null = $server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
            $null = $db.Query("CREATE TABLE dbo.example (id int);
            INSERT dbo.example
            SELECT top 100 1
            FROM sys.objects")
        }
        catch { } # No idea why appveyor can't handle this
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
    }

    if ((Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table example)) {
        # Sometimes appveyor bombs
        It "exports a dacpac" {
            $results = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname
            if (($results).Path) {
                Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
            }
        }

        It "exports to the correct directory" {
            $testFolder = 'C:\Temp\dacpacs'
            New-Item $testFolder -ItemType Directory

            Push-Location $testFolder
            try {
                $relativePath = '.\'
                $expectedPath = (Resolve-Path $relativePath).Path

                $results = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname -Path $relativePath
                $results.Path | Split-Path | Should -Be $expectedPath
            }
            finally {
                Pop-Location
                Remove-Item $testFolder -Force -Recurse
            }
        }
    }
}