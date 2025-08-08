#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Backup-DbaServiceMasterKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "KeyCredential",
                "SecurePassword",
                "Path",
                "FileBaseName",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Can backup a service master key" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
        }

        It "backs up the SMK" {
            $backupResults = Backup-DbaServiceMasterKey -SqlInstance $TestConfig.instance1 -SecurePassword $securePassword -Confirm:$false
            $backupResults.Status | Should -Be "Success"
            $null = Remove-Item -Path $backupResults.Path -ErrorAction SilentlyContinue -Confirm:$false
        }

        It "backs up the SMK with a specific filename (see #9483)" {
            $randomNum = Get-Random
            $fileBackupResults = Backup-DbaServiceMasterKey -SqlInstance $TestConfig.instance1 -SecurePassword $securePassword -FileBaseName "smk($randomNum)" -Confirm:$false
            [IO.Path]::GetFileNameWithoutExtension($fileBackupResults.Path) | Should -Be "smk($randomNum)"
            $fileBackupResults.Status | Should -Be "Success"
            $null = Remove-Item -Path $fileBackupResults.Path -ErrorAction SilentlyContinue -Confirm:$false
        }
    }
}
