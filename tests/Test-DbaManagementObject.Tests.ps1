param($ModuleName = 'dbatools')

Describe "Test-DbaManagementObject" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaManagementObject
        }
        It "Should have ComputerName as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have VersionNumber as a non-mandatory parameter of type System.Int32[]" {
            $CommandUnderTest | Should -HaveParameter VersionNumber -Type System.Int32[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Mandatory:$false
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $versionMajor = $server.VersionMajor
        }

        It "Should have correct properties" {
            $trueResults = Test-DbaManagementObject -ComputerName $global:instance2 -VersionNumber $versionMajor
            $ExpectedProps = 'ComputerName', 'Version', 'Exists'
            ($trueResults[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should return true for VersionNumber $versionMajor" {
            $trueResults = Test-DbaManagementObject -ComputerName $global:instance2 -VersionNumber $versionMajor
            $trueResults.Exists | Should -Be $true
        }

        It "Should return false for VersionNumber -1" {
            $falseResults = Test-DbaManagementObject -ComputerName $global:instance2 -VersionNumber -1
            $falseResults.Exists | Should -Be $false
        }
    }
}
