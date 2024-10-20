param($ModuleName = 'dbatools')

Describe "Set-DbaAvailabilityGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAvailabilityGroup
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "AvailabilityGroup",
            "AllAvailabilityGroups",
            "DtcSupportEnabled",
            "ClusterType",
            "AutomatedBackupPreference",
            "FailureConditionLevel",
            "HealthCheckTimeout",
            "BasicAvailabilityGroup",
            "DatabaseHealthTrigger",
            "IsDistributedAvailabilityGroup",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

Describe "Set-DbaAvailabilityGroup Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $agname = "dbatoolsci_agroup"
        $null = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }

    AfterAll {
        Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
    }

    Context "Sets AG properties" {
        It "Returns modified results" {
            $results = Set-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -DtcSupportEnabled:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.DtcSupportEnabled | Should -Be $false
        }

        It "Returns newly modified results" {
            $results = Set-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -DtcSupportEnabled
            $results.AvailabilityGroup | Should -Be $agname
            $results.DtcSupportEnabled | Should -Be $true
        }
    }
} #$global:instance2 for appveyor
