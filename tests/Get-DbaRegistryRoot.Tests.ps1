$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command returns proper info" {
        $results = Get-DbaRegistryRoot
        $regexpath = "Software\\Microsoft\\Microsoft SQL Server"

        if ($results.count -gt 1) {
            It "returns at least one named instance if more than one result is returned" {
                $named = $results | Where-Object SqlInstance -match '\\'
                $named.SqlInstance.Count -gt 0 | Should Be $true
            }
        }

        foreach ($result in $results) {
            It "returns non-null values" {
                $result.Hive | Should Not Be $null
                $result.SqlInstance | Should Not Be $null
            }

            It "matches Software\Microsoft\Microsoft SQL Server" {
                $result.RegistryRoot -match $regexpath | Should Be $true
            }
        }
    }
}