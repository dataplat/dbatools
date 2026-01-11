#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaMultiTool",
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
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Testing DBA MultiTool installer with download" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $branch = "main"
            $database = "dbatoolsci_multitool_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $database

            $resultsDownload = Install-DbaMultiTool -SqlInstance $TestConfig.InstanceMulti1 -Database $database -Branch $branch -Force -Verbose:$false

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $database -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs to specified database: $database" {
            $resultsDownload[0].Database -eq $database | Should -Be $true
        }
        It "Shows status of Installed" {
            $resultsDownload[0].Status -eq "Installed" | Should -Be $true
        }
        It "Installed sp_doc, sp_helpme, sp_sizeoptimiser, and sp_estindex" {
            "sp_doc", "sp_helpme", "sp_sizeoptimiser", "sp_estindex" | Should -BeIn $resultsDownload.Name
        }
        It "Has the correct properties" {
            $result = $resultsDownload[0]
            $ExpectedProps = "SqlInstance,InstanceName,ComputerName,Name,Status,Database".Split(",")
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
        It "Shows status of Updated" {
            $resultsDownload = Install-DbaMultiTool -SqlInstance $TestConfig.InstanceMulti1 -Database $database -Verbose:$false
            $resultsDownload[0].Status -eq "Updated" | Should -Be $true
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "dba-multitool-$branch"
            $sqlScript = Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1
            Add-Content $sqlScript.FullName (New-Guid).ToString()
            $result = Install-DbaMultiTool -SqlInstance $TestConfig.InstanceMulti1 -Database $database -Verbose:$false -WarningAction SilentlyContinue
            $result = $result | Where-Object Name -eq $sqlScript.BaseName
            $result.Status -eq "Error" | Should -Be $true
        }
    }
    Context "Testing DBA MultiTool installer with LocalFile" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $branch = "main"
            $database = "dbatoolsci_multitool_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
            $server.Query("CREATE DATABASE $database")

            $tempDir = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Type Container -Path $tempDir

            $outfile = "$tempDir\dba-multitool-$branch.zip"
            Invoke-WebRequest -Uri "https://github.com/LowlyDBA/dba-multitool/archive/$branch.zip" -OutFile $outfile
            $resultsLocalFile = Install-DbaMultiTool -SqlInstance $TestConfig.InstanceMulti2 -Database $database -Branch $branch -LocalFile $outfile -Force

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $database -ErrorAction SilentlyContinue

            Remove-Item -Path $tempDir -Force -Recurse -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs to specified database: $database" {
            $resultsLocalFile[0].Database -eq $database | Should -Be $true
        }
        It "Shows status of Installed" {
            $resultsLocalFile[0].Status -eq "Installed" | Should -Be $true
        }
        It "Installed sp_doc, sp_helpme, sp_sizeoptimiser, and sp_estindex" {
            "sp_doc", "sp_helpme", "sp_sizeoptimiser", "sp_estindex" | Should -BeIn $resultsLocalFile.Name
        }
        It "Has the correct properties" {
            $result = $resultsLocalFile[0]
            $ExpectedProps = "SqlInstance,InstanceName,ComputerName,Name,Status,Database".Split(",")
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
        It "Shows status of Updated" {
            $resultsLocalFile = Install-DbaMultiTool -SqlInstance $TestConfig.InstanceMulti2 -Database $database
            $resultsLocalFile[0].Status -eq "Updated" | Should -Be $true
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "dba-multitool-$branch"
            $sqlScript = Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1
            Add-Content $sqlScript.FullName (New-Guid).ToString()
            $result = Install-DbaMultiTool -SqlInstance $TestConfig.InstanceMulti2 -Database $database -Verbose:$false -WarningAction SilentlyContinue
            $result = $result | Where-Object Name -eq $sqlScript.BaseName
            $result.Status -eq "Error" | Should -Be $true
        }
    }
}