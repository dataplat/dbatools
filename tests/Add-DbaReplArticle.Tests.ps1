$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Tests" {
    # Unit Tests
    Describe "Unit Tests" -Tag 'UnitTests' {
        It "Validate parameters" {
            [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
            [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Publication', 'Schema', 'Name', 'Filter', 'CreationScriptOptions', 'EnableException'
            $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
            $params | Should -BeExactly $knownParameters
        }
    }
}
<#
    Integration tests for replication are in GitHub Actions and run from \tests\gh-actions-repl-*.ps1.ps1
#>
