param($ModuleName = 'dbatools')

Describe "Test-DbaTempDbConfig" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaTempDbConfig
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works on $global:instance2" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $results = Test-DbaTempDbConfig -SqlInstance $server
        }

        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Rule', 'Recommended', 'CurrentSetting', 'IsBestPractice', 'Notes'
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should return correct IsBestPractice for 'File Location' rule" {
            $rule = 'File Location'
            $isBestPractice = $server.Databases['tempdb'].FileGroups[0].Files[0].FileName.Substring(0, 1) -ne 'C'
            ($results | Where-Object Rule -match $rule).IsBestPractice | Should -Be $isBestPractice
        }

        It "Should return false for Recommended with 'File Location' rule" {
            $rule = 'File Location'
            ($results | Where-Object Rule -match $rule).Recommended | Should -Be $false
        }

        It "Should return correct Recommended for 'TF 1118 Enabled' rule" {
            $rule = 'TF 1118 Enabled'
            $recommended = $server.VersionMajor -lt 13
            ($results | Where-Object Rule -match $rule).Recommended | Should -Be $recommended
        }
    }
}
