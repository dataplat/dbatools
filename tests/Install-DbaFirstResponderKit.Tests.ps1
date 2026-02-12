#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaFirstResponderKit",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Branch",
                "Database",
                "LocalFile",
                "OnlyScript",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Testing First Responder Kit installer with download" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $database = "dbatoolsci_frk_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $server.Query("CREATE DATABASE $database")

            $resultsDownload = Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti1 -Database $database -Branch main -Force

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $database

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs to specified database: $database" {
            $resultsDownload[0].Database -eq $database | Should -Be $true
        }
        It "Shows status of Installed" {
            $resultsDownload[0].Status -eq "Installed" | Should -Be $true
        }
        It "At least installed sp_Blitz and sp_BlitzIndex" {
            "sp_Blitz", "sp_BlitzIndex" | Should -BeIn $resultsDownload.Name
        }
        It "has the correct properties" {
            $result = $resultsDownload[0]
            $ExpectedProps = "SqlInstance", "InstanceName", "ComputerName", "Name", "Status", "Database"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
        It "Shows status of Updated" {
            $resultsDownload = Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti1 -Database $database
            $resultsDownload[0].Status -eq "Updated" | Should -Be $true
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "SQL-Server-First-Responder-Kit-main"
            $sqlScript = (Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1).FullName
            Add-Content $sqlScript (New-Guid).ToString()
            $result = Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti1 -Database $database -WarningAction SilentlyContinue
            $result[0].Status -eq "Error" | Should -Be $true
        }
        It "Returns output of the documented type" {
            $resultsDownload | Should -Not -BeNullOrEmpty
            $resultsDownload[0] | Should -BeOfType PSCustomObject
        }
        It "Has the expected properties" {
            $resultsDownload | Should -Not -BeNullOrEmpty
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Name", "Status")
            foreach ($prop in $expectedProps) {
                $resultsDownload[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
        It "Has no additional unexpected properties" {
            $resultsDownload | Should -Not -BeNullOrEmpty
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Name", "Status")
            $resultsDownload[0].PSObject.Properties.Name | Should -HaveCount $expectedProps.Count
        }
    }

    Context "Testing First Responder Kit installer with LocalFile" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $tempDir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Type Container -Path $tempDir

            $database = "dbatoolsci_frk_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
            $server.Query("CREATE DATABASE $database")

            $outfile = "$tempDir\SQL-Server-First-Responder-Kit-main.zip"
            Invoke-WebRequest -Uri "https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/main.zip" -OutFile $outfile
            $resultsLocalFile = Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti2 -Database $database -Branch main -LocalFile $outfile -Force

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $database

            Remove-Item -Path $tempDir -Force -Recurse -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs to specified database: $database" {
            $resultsLocalFile[0].Database -eq $database | Should -Be $true
        }
        It "Shows status of Installed" {
            $resultsLocalFile[0].Status -eq "Installed" | Should -Be $true
        }
        It "At least installed sp_Blitz and sp_BlitzIndex" {
            "sp_Blitz", "sp_BlitzIndex" | Should -BeIn $resultsLocalFile.Name
        }
        It "Has the correct properties" {
            $result = $resultsLocalFile[0]
            $ExpectedProps = "SqlInstance", "InstanceName", "ComputerName", "Name", "Status", "Database"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
        It "Shows status of Updated" {
            $resultsLocalFile = Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti2 -Database $database
            $resultsLocalFile[0].Status -eq "Updated" | Should -Be $true
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "SQL-Server-First-Responder-Kit-main"
            $sqlScript = (Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1).FullName
            Add-Content $sqlScript (New-Guid).ToString()
            $result = Install-DbaFirstResponderKit -SqlInstance $TestConfig.InstanceMulti2 -Database $database -WarningAction SilentlyContinue
            $result[0].Status -eq "Error" | Should -Be $true
        }
    }

}