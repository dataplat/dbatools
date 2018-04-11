$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        $paramCount = 3
        <#
            Get commands, Default count = 11
            Commands with SupportShouldProcess = 13
        #>
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Test-PSRemoting).Parameters.Keys
        $knownParameters = 'ComputerName', 'Credential', 'EnableException'
        It "Contains our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Contains $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
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