param($ModuleName = 'dbatools')

Describe "Get-DbaAgListener Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgListener
        }
        It "has the required parameter: SqlInstance" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "AvailabilityGroup",
                "Listener",
                "InputObject",
                "EnableException"
            )
            $params | ForEach-Object {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }
}

Describe "Get-DbaAgListener Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $SkipIntegrationTests = [Environment]::GetEnvironmentVariable('SkipDbaToolsIntegrationTests') -eq 'true'
    }

    BeforeAll {
        if (-not $SkipIntegrationTests) {
            $agname = "dbatoolsci_ag_listener"
            $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert
            $ag | Add-DbaAgListener -IPAddress 127.0.20.1 -Port 14330
        }
    }

    AfterAll {
        if (-not $SkipIntegrationTests) {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname
        }
    }

    Context "Gets availability group listeners" -Skip:$SkipIntegrationTests {
        It "Returns results with proper data" {
            $results = Get-DbaAgListener -SqlInstance $global:instance3
            $results.PortNumber | Should -Contain 14330
        }
    }
} #$global:instance2 for appveyor
