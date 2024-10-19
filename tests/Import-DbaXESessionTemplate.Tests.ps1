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
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have Template as a parameter" {
            $CommandUnderTest | Should -HaveParameter Template
        }
        It "Should have TargetFilePath as a parameter" {
            $CommandUnderTest | Should -HaveParameter TargetFilePath
        }
        It "Should have TargetFileMetadataPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter TargetFileMetadataPath
        }
        It "Should have StartUpState as a parameter" {
            $CommandUnderTest | Should -HaveParameter StartUpState
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
