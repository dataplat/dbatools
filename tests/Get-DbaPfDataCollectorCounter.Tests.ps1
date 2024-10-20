param($ModuleName = 'dbatools')

Describe "Get-DbaPfDataCollectorCounter" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPfDataCollectorCounter
        }
        $requiredParameters = @(
            "ComputerName",
            "Credential",
            "CollectorSet",
            "Collector",
            "Counter",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $requiredParameters {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Verifying command works" {
        It "returns a result with the right computername and name is not null" {
            $results = Get-DbaPfDataCollectorCounter | Select-Object -First 1
            $results.ComputerName | Should -Be $env:COMPUTERNAME
            $results.Name | Should -Not -BeNullOrEmpty
        }
    }
}
