$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'ComputerName', 'UserName', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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