$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Session', 'Path', 'FilePath', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    AfterAll {
        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session db_ola_health | Remove-DbaXESession
        Remove-Item -Path 'C:\windows\temp\Profiler TSQL Duration.xml' -ErrorAction SilentlyContinue
    }
    Context "Test Importing Session Template" {
        $session = Import-DbaXESessionTemplate -SqlInstance $script:instance2 -Template 'Profiler TSQL Duration'
        $results = $session | Export-DbaXESessionTemplate -Path C:\windows\temp
        It "session exports to disk" {
            $results.Name | Should Be 'Profiler TSQL Duration.xml'
        }
    }
}