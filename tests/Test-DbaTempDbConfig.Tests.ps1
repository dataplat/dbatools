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
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
