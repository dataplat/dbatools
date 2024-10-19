param($ModuleName = 'dbatools')

Describe "Backup-DbaServiceMasterKey" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Backup-DbaServiceMasterKey
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "KeyCredential",
                "SecurePassword",
                "Path",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Can backup a service master key" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $results = Backup-DbaServiceMasterKey -SqlInstance $global:instance1 -Confirm:$false -SecurePassword $securePassword
        }

        AfterAll {
            Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false
        }

        It "backs up the SMK" {
            $results.Status | Should -Be "Success"
        }
    }
}
