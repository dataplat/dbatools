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

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Name",
            "Path",
            "Template",
            "TargetFilePath",
            "TargetFileMetadataPath",
            "StartUpState",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
