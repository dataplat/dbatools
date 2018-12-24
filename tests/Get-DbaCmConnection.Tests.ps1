$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\Get-DbaCmConnection).Parameters.Keys
        $knownParameters = 'ComputerName', 'UserName', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        New-DbaCmConnection -ComputerName $env:COMPUTERNAME
    }
    AfterAll {
        Remove-DbaCmConnection -ComputerName $env:COMPUTERNAME -Confirm:$False
    }
    Context "Returns DbaCmConnection" {
        $Results = Get-DbaCMConnection -ComputerName $env:COMPUTERNAME
        It "Results are not Empty" {
           $Results | should not be $null
        }
    }
    Context "Returns DbaCmConnection for User" {
        $Results = Get-DbaCMConnection -ComputerName $env:COMPUTERNAME -UserName *
        It "Results are not Empty" {
           $Results | should not be $null
        }
    }
}