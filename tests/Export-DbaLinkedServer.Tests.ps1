#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaLinkedServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "LinkedServer",
                "SqlCredential",
                "Credential",
                "Path",
                "FilePath",
                "ExcludePassword",
                "Append",
                "Passthru",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create a linked server for testing
            $linkedServerName = "dbatoolsci_exportls_$(Get-Random)"
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "EXEC sp_addlinkedserver @server = N'$linkedServerName', @srvproduct = N'SQL Server'"

            $exportPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
            $null = New-Item -Path $exportPath -ItemType Directory

            # Test Passthru output (returns string)
            $resultPassthru = Export-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle -LinkedServer $linkedServerName -ExcludePassword -Passthru

            # Test file output (returns FileInfo)
            $exportFile = "$exportPath\$linkedServerName.sql"
            $resultFile = Export-DbaLinkedServer -SqlInstance $TestConfig.InstanceSingle -LinkedServer $linkedServerName -ExcludePassword -FilePath $exportFile

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database master -Query "EXEC sp_dropserver @server = '$linkedServerName'" -ErrorAction SilentlyContinue
            Remove-Item -Path $exportPath -Recurse -ErrorAction SilentlyContinue
        }

        It "Returns string output with Passthru" {
            $resultPassthru | Should -Not -BeNullOrEmpty
        }

        It "Returns string type with Passthru" {
            if (-not $resultPassthru) { Set-ItResult -Skipped -Because "no result to validate" }
            $resultPassthru | Should -BeOfType [System.String]
        }

        It "Returns T-SQL content with Passthru" {
            if (-not $resultPassthru) { Set-ItResult -Skipped -Because "no result to validate" }
            "$resultPassthru" | Should -Match "sp_addlinkedserver"
        }

        It "Returns FileInfo when writing to file" {
            $resultFile | Should -Not -BeNullOrEmpty
        }

        It "Returns FileInfo type when writing to file" {
            if (-not $resultFile) { Set-ItResult -Skipped -Because "no result to validate" }
            $resultFile | Should -BeOfType [System.IO.FileInfo]
        }

        It "Returns a file that exists on disk" {
            if (-not $resultFile) { Set-ItResult -Skipped -Because "no result to validate" }
            $resultFile.FullName | Should -Exist
        }
    }
}