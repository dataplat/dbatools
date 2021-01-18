$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

# required to support internal functions that utilize Write-Message
Import-Module ([IO.Path]::Combine(([string]$PSScriptRoot).Trim("tests"), 'src\bin', 'dbatools.dll'))
. ([IO.Path]::Combine(([string]$PSScriptRoot).Trim("tests"), 'src\internal\functions\message', 'Convert-DbaMessageTarget.ps1'))
. ([IO.Path]::Combine(([string]$PSScriptRoot).Trim("tests"), 'src\internal\functions\message', 'Convert-DbaMessageException.ps1'))
. ([IO.Path]::Combine(([string]$PSScriptRoot).Trim("tests"), 'src\internal\functions', 'Get-ErrorMessage.ps1'))
. ([IO.Path]::Combine(([string]$PSScriptRoot).Trim("tests"), 'src\internal\functions\flowcontrol', 'Stop-Function.ps1'))
. ([IO.Path]::Combine(([string]$PSScriptRoot).Trim("tests"), 'src\internal\functions', 'Test-PSRemoting.ps1'))

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Validate parameters" {
        [array]$knownParameters = 'ComputerName', 'Credential', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
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