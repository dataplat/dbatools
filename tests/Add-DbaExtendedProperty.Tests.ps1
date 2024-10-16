$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandUnderTest = Get-Command $CommandName
    }

    Context "Validate parameters" {
        It "Should have the correct parameters" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Name -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Value -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InputObject -Type PSObject[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Verbose -Type SwitchParameter -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Debug -Type SwitchParameter -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32 -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter WhatIf -Type SwitchParameter -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Confirm -Type SwitchParameter -Not -Mandatory
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $server2 = Connect-DbaInstance -SqlInstance $script:instance2
        $null = Get-DbaProcess -SqlInstance $server2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
        $newDbName = "dbatoolsci_newdb_$random"
        $db = New-DbaDatabase -SqlInstance $server2 -Name $newDbName
    }

    AfterAll {
        $null = $db | Remove-DbaDatabase -Confirm:$false
    }

    Context "commands work as expected" {
        It "adds an extended property" {
            $ep = $db | Add-DbaExtendedProperty -Name "Test_Database_Name" -Value "Sup"
            $ep.Name | Should -Be "Test_Database_Name"
            $ep.ParentName | Should -Be $db.Name
            $ep.Value | Should -Be "Sup"
        }
    }
}
