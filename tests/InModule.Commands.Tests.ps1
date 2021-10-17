$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "duplicate commands are not added" {
        It "only indexes one instance per command" {
            $sourcePath = [IO.Path]::Combine((Split-Path $PSScriptRoot -Parent), 'src')
            $commandlist = Import-PowerShellDataFile -Path "$sourcePath\dbatools.psd1"
            $dupes = $commandlist.FunctionsToExport | Group-Object | Where-Object Count -gt 1
            $dupes.Name | Should -be $null
        }
    }
}