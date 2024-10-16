$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandUnderTest = Get-Command $CommandName
    }

    Context "Validate parameters" {
        It "Should have the correct parameters" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter CollectorSet -Type String[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Collector -Type String[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Counter -Type Object[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate |
            Get-DbaPfDataCollector | Get-DbaPfDataCollectorCounter -Counter '\LogicalDisk(*)\Avg. Disk Queue Length' | Remove-DbaPfDataCollectorCounter -Confirm:$false
    }
    AfterAll {
        $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
    }
    Context "Verifying command returns all the required results" {
        It "returns the correct values" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Get-DbaPfDataCollector | Add-DbaPfDataCollectorCounter -Counter '\LogicalDisk(*)\Avg. Disk Queue Length'
            $results.DataCollectorSet | Should -Be 'Long Running Queries'
            $results.Name | Should -Be '\LogicalDisk(*)\Avg. Disk Queue Length'
        }
    }
}
