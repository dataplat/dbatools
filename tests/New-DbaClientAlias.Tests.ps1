$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "adds the alias" {
        $results = New-DbaClientAlias -ServerName sql2016 -Alias dbatoolscialias-new -Verbose:$false
        It "returns accurate information" {
            $results.AliasName | Should Be dbatoolscialias-new, dbatoolscialias-new
        }
        $results | Remove-DbaClientAlias
    }
}