$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "duplicate commands are not added" {
        It "only indexes one instance per command" {
            # this no longer works in PS 5.1, no idea why, maybe it doesn't like the new test for core or desktop
            # $commandlist = Import-PowerShellDataFile -Path '$PSScriptRoot\..\dbatools.psd1'
            $commandlist = Invoke-Expression (Get-Content '$PSScriptRoot\..\dbatools.psd1' -Raw)
            $dupes = $commandlist.FunctionsToExport | Group-Object | Where-Object Count -gt 1
            $dupes.Name | Should -be $null
        }
    }
}