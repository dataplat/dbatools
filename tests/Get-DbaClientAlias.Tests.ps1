$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\Get-DbaClientAlias).Parameters.Keys
        $knownParameters = 'ComputerName', 'Credential', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $newalias = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias -Verbose:$false
    }
    AfterAll {
        $newalias | Remove-DbaClientAlias
    }

    Context "gets the alias" {
        $results = Get-DbaClientAlias
        It "returns accurate information" {
            $results.AliasName -contains 'dbatoolscialias' | Should Be $true
        }
    }
}