#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Backup-DbaServiceMasterKey" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Backup-DbaServiceMasterKey
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "KeyCredential",
                "SecurePassword",
                "Path",
                "FileBaseName",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Backup-DbaServiceMasterKey" -Tag "IntegrationTests" {
    Context "Can backup a service master key" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
        }

        It "backs up the SMK" {
            $results = Backup-DbaServiceMasterKey -SqlInstance $TestConfig.instance1 -SecurePassword $securePassword -Confirm:$false
            $results.Status | Should -Be "Success"
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false
        }

        It "backs up the SMK with a specific filename (see #9483)" {
            $random = Get-Random
            $results = Backup-DbaServiceMasterKey -SqlInstance $TestConfig.instance1 -SecurePassword $securePassword -FileBaseName "smk($random)" -Confirm:$false
            [IO.Path]::GetFileNameWithoutExtension($results.Path) | Should -Be "smk($random)"
            $results.Status | Should -Be "Success"
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false
        }
    }
}
