$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    BeforeAll {
        # Import module or set up test environment if needed
    }

    Context "Validate parameters" {
        BeforeAll {
            $Command = Get-Command -Name $CommandName
            $CommonParameters = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'WhatIf', 'Confirm')
        }

        It "Should have the correct parameters" {
            $Command | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
            $Command | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
            $Command | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
            foreach ($Param in $CommonParameters) {
                $Command | Should -HaveParameter $Param
            }
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*:SqlInstance"] = $script:instance2
        $null = Remove-DbaDbMirrorMonitor -SqlInstance $script:instance2 -WarningAction SilentlyContinue
    }

    AfterAll {
        $null = Remove-DbaDbMirrorMonitor -SqlInstance $script:instance2 -WarningAction SilentlyContinue
    }

    It "adds the mirror monitor" {
        $results = Add-DbaDbMirrorMonitor -WarningAction SilentlyContinue
        $results.MonitorStatus | Should -Be 'Added'
    }
}
