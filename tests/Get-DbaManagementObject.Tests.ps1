$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'VersionNumber', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe "Get-DbaManagementObject Integration Test" -Tag "IntegrationTests" {
    $results = Get-DbaManagementObject -ComputerName $env:COMPUTERNAME

    It "returns results" {
        $results.Count -gt 0 | Should Be $true
    }
    It "has the correct properties" {
        $result = $results[0]
        $ExpectedProps = 'ComputerName,Version,Loaded,LoadTemplate'.Split(',')
        ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
    }

    $results = Get-DbaManagementObject -ComputerName $env:COMPUTERNAME -VersionNumber 10
    It "Returns the version specified" {
        $results | Should Not Be $null
    }
}