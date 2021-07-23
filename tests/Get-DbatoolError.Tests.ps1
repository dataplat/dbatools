$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'First', 'Last', 'Skip', 'All'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Gets an error" {
        It "doesn't return non-dbatools errors" {
            $null = Get-ChildItem doesntexist -ErrorAction SilentlyContinue
            Get-DbatoolsError | Should -BeNullOrEmpty
        }
        It "returns a dbatools error" {
            $null = Connect-DbaInstance -SqlInstance nothing -ConnectTimeout 1
            Get-DbatoolsError | Should -Not -BeNullOrEmpty
        }
    }
}