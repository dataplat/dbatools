param($ModuleName = 'dbatools')

Describe "Import-DbaXESessionTemplate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Import-DbaXESessionTemplate
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type System.String
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String[]
        }
        It "Should have Template as a parameter" {
            $CommandUnderTest | Should -HaveParameter Template -Type System.String[]
        }
        It "Should have TargetFilePath as a parameter" {
            $CommandUnderTest | Should -HaveParameter TargetFilePath -Type System.String
        }
        It "Should have TargetFileMetadataPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter TargetFileMetadataPath -Type System.String
        }
        It "Should have StartUpState as a parameter" {
            $CommandUnderTest | Should -HaveParameter StartUpState -Type System.String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
    }

    Context "Test Importing Session Template" {
        BeforeAll {
            $global:instanceName = $global:instance2
        }

        AfterAll {
            $null = Get-DbaXESession -SqlInstance $global:instanceName -Session 'Overly Complex Queries' | Remove-DbaXESession
        }

        It "Session imports with proper name and non-default target file location" -Skip {
            $result = Import-DbaXESessionTemplate -SqlInstance $global:instanceName -Template 'Overly Complex Queries' -TargetFilePath C:\temp
            $result.Name | Should -Be "Overly Complex Queries"
            $result.TargetFile | Should -Match 'C:\\temp'
        }
    }
}
