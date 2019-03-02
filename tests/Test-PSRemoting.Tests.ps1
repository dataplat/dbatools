$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Test-PSRemoting.ps1"


Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "returns a boolean with no exceptions" {
        $result = Test-PSRemoting -ComputerName "funny"
        It "returns $false when failing" {
            $result | Should Be $false
        }
        $result = Test-PSRemoting -ComputerName localhost
        It "returns $true when succeeding" {
            $result | Should Be $true
        }
    }
    Context "handles an instance, using just the computername" {
        $result = Test-PSRemoting -ComputerName $script:instance1
        It "returns $true when succeeding" {
            $result | Should Be $true
        }
    }
}