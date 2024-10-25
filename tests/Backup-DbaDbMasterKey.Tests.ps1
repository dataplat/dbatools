#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = "dbatools")
$global:TestConfig = Get-TestConfig

Describe "Backup-DbaDbMasterKey" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Backup-DbaDbMasterKey
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "Database",
                "ExcludeDatabase",
                "SecurePassword",
                "Path",
                "InputObject",
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Backup-DbaDbMasterKey" -Tag "IntegrationTests" {
    Context "Can backup a database master key" {
        BeforeAll {
            $instance = $TestConfig.instance1
            $database = "tempdb"
            $password = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

            if (-not (Get-DbaDbMasterKey -SqlInstance $instance -Database $database)) {
                $null = New-DbaDbMasterKey -SqlInstance $instance -Database $database -Password $password -Confirm:$false
            }

            $splatBackup = @{
                SqlInstance = $instance
                Database = $database
                SecurePassword = $password
                Confirm = $false
            }
        }

        AfterAll {
            Get-DbaDbMasterKey -SqlInstance $instance -Database $database | Remove-DbaDbMasterKey -Confirm:$false
        }

        It "Backs up the database master key" {
            $results = Backup-DbaDbMasterKey @splatBackup
            $results | Should -Not -BeNullOrEmpty
            $results.Database | Should -Be $database
            $results.Status | Should -Be "Success"
            $results.DatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $instance -Database $database).ID

            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false
        }
    }
}
