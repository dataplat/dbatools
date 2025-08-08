#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Backup-DbaDbMasterKey",
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
                "Credential",
                "Database",
                "ExcludeDatabase",
                "SecurePassword",
                "Path",
                "FileBaseName",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Can backup a database master key" {
        BeforeAll {
            $instance = $TestConfig.instance1
            $database = "tempdb"
            $password = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force

            if (-not (Get-DbaDbMasterKey -SqlInstance $instance -Database $database)) {
                $null = New-DbaDbMasterKey -SqlInstance $instance -Database $database -Password $password -Confirm:$false
            }
        }

        AfterAll {
            Get-DbaDbMasterKey -SqlInstance $instance -Database $database | Remove-DbaDbMasterKey -Confirm:$false
        }

        It "Backs up the database master key" {
            $splatBackup = @{
                SqlInstance    = $instance
                Database       = $database
                SecurePassword = $password
                Confirm        = $false
            }
            $results = Backup-DbaDbMasterKey @splatBackup
            $results | Should -Not -BeNullOrEmpty
            $results.Database | Should -Be $database
            $results.Status | Should -Be "Success"
            $results.DatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $instance -Database $database).ID

            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false
        }

        It "Backs up the database master key with a specific filename (see #9484)" {
            $random = Get-Random
            $splatBackup = @{
                SqlInstance    = $instance
                Database       = $database
                SecurePassword = $password
                FileBaseName   = "dbatoolscli_dbmasterkey_$random"
                Confirm        = $false
            }
            $results = Backup-DbaDbMasterKey @splatBackup
            $results | Should -Not -BeNullOrEmpty
            $results.Database | Should -Be $database
            $results.Status | Should -Be "Success"
            $results.DatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $instance -Database $database).ID
            [IO.Path]::GetFileNameWithoutExtension($results.Path) | Should -Be "dbatoolscli_dbmasterkey_$random"
            $null = Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false
        }

    }
}
