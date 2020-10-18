$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'IncludeWindows', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Gets SQL Server Install Date" {
        $results = Get-DbaInstanceInstallDate -SqlInstance $script:instance2
        It "Gets results" {
            $results | Should Not Be $null
        }
    }
    Context "Gets SQL Server Install Date and Windows Install Date" {
        $results = Get-DbaInstanceInstallDate -SqlInstance $script:instance2 -IncludeWindows
        It "Gets results" {
            $results | Should Not Be $null
        }
    }
}