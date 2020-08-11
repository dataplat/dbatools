$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "duplicate commands are not added" {
        It "only indexes one instance per command" {
            $commandlist = Import-PowerShellDataFile -Path '$PSScriptRoot\..\dbatools.psd1'
            $dupes = $commandlist.FunctionsToExport | Group-Object | Where-Object Count -gt 1
            $dupes.Name | Should -be $null
        }
    }
}