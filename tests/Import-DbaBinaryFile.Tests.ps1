#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaBinaryFile",
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
                "Database",
                "Table",
                "Schema",
                "Statement",
                "FileNameColumn",
                "BinaryColumn",
                "NoFileNameColumn",
                "InputObject",
                "FilePath",
                "Path",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $dbName = "dbatoolsci_binaryfile_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbName

        $splatTable = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $dbName
            Query       = "CREATE TABLE dbo.BinaryFiles (FileName nvarchar(255), FileData varbinary(max))"
        }
        $null = Invoke-DbaQuery @splatTable

        # Two files, because the command used to close the connection after every single one of them.
        $importPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $importPath -ItemType Directory
        Set-Content -Path "$importPath\first.txt" -Value "first file"
        Set-Content -Path "$importPath\second.txt" -Value "second file"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbName
        Remove-Item -Path $importPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Importing through a connection of the caller (#10554)" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            # The connection is in use and therefore open, which is what the command has to cope with.
            $null = $callerServer.ConnectionContext.ExecuteNonQuery("CREATE TABLE #dbatoolsci_marker (id INT)")

            $splatImport = @{
                SqlInstance = $callerServer
                Database    = $dbName
                Table       = "BinaryFiles"
                Path        = $importPath
            }
            $importResults = Import-DbaBinaryFile @splatImport

            $splatCount = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $dbName
                Query       = "SELECT COUNT(*) FROM dbo.BinaryFiles"
                As          = "SingleValue"
            }
            $importedRows = Invoke-DbaQuery @splatCount

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $callerServer | Disconnect-DbaInstance

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "imports every file" {
            $importResults.Status | Should -Be "Success", "Success"
            $importedRows | Should -Be 2
        }

        It "leaves the connection open, so the session survives" {
            { $callerServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM #dbatoolsci_marker") } | Should -Not -Throw
        }
    }
}
