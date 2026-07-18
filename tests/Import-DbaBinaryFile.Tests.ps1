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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # A known 64-byte payload on disk and a dedicated table with an auto-detectable filename
        # column (matches the phrase "name") and a varbinary column (auto-detected as the binary
        # target). WriteAllBytes is a static method, not a constructor - allowed under the v3 rule.
        $random = Get-Random
        $sourceDir = Join-Path -Path $TestConfig.Temp -ChildPath "dbatoolsci_binfile_$random"
        $splatNewDir = @{
            ItemType = "Directory"
            Force    = $true
            Path     = $sourceDir
        }
        $null = New-Item @splatNewDir
        $sourceFile = Join-Path -Path $sourceDir -ChildPath "payload_$random.bin"
        [System.IO.File]::WriteAllBytes($sourceFile, [byte[]](1..64))

        $db = "dbatoolsci_binfile_$random"
        $tableName = "BinaryFiles"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $db
        $splatCreate = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $db
            Query       = "CREATE TABLE dbo.$tableName ([FileName] NVARCHAR(500) NULL, [TheFile] VARBINARY(MAX) NULL)"
        }
        $null = Invoke-DbaQuery @splatCreate

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            if ($db) {
                $splatRemove = @{
                    SqlInstance = $TestConfig.InstanceSingle
                    Database    = $db
                    ErrorAction = "SilentlyContinue"
                }
                $null = Remove-DbaDatabase @splatRemove
            }
            $splatCleanupDir = @{
                Path        = $sourceDir
                Recurse     = $true
                Force       = $true
                ErrorAction = "SilentlyContinue"
            }
            Remove-Item @splatCleanupDir
        } finally {
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Input validation" {
        It "Warns when neither Database and Table nor a piped table is supplied" {
            # -Table omitted, and nothing piped, trips the first guard before any connection.
            $splatNoTable = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $db
                Path            = $sourceDir
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaBinaryFile @splatNoTable
            $result | Should -BeNullOrEmpty
            $warn -join " " | Should -Match "must specify either Database and Table or pipe in a table"
        }

        It "Warns when both -Path and -FilePath are supplied" {
            $splatBoth = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $db
                Table           = $tableName
                Path            = $sourceDir
                FilePath        = $sourceFile
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaBinaryFile @splatBoth
            $result | Should -BeNullOrEmpty
            $warn -join " " | Should -Match "cannot specify both -Path and -FilePath"
        }

        It "Warns when neither -Path nor -FilePath is supplied" {
            $splatNeither = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $db
                Table           = $tableName
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaBinaryFile @splatNeither
            $result | Should -BeNullOrEmpty
            # characterization: the message keeps the source grammar quirk ("either" means "neither")
            $warn -join " " | Should -Match "cannot specify either -Path or -FilePath"
        }

        It "Warns when -FilePath does not exist" {
            $missingFile = Join-Path -Path $sourceDir -ChildPath "does_not_exist_$random.bin"
            $splatMissing = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = $db
                Table           = $tableName
                FilePath        = $missingFile
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaBinaryFile @splatMissing
            $result | Should -BeNullOrEmpty
            $warn -join " " | Should -Match "File .* does not exist"
        }
    }

    Context "Importing a file" {
        It "Auto-detects the columns, returns a Success object, and lands the row" {
            $splatImport = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $db
                Table       = $tableName
                FilePath    = $sourceFile
                Confirm     = $false
            }
            $result = Import-DbaBinaryFile @splatImport
            $result.Status | Should -Be "Success"
            $result.Database | Should -Be $db
            $result.Table | Should -Be $tableName
            $result.FilePath | Should -Be $sourceFile
            foreach ($prop in "ComputerName", "InstanceName", "SqlInstance", "Database", "Table", "FilePath", "Status") {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }

            # the row actually landed: the filename column holds the leaf name and the binary column
            # holds all 64 payload bytes (auto-detected FileName + TheFile columns).
            $splatRead = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $db
                Query       = "SELECT [FileName] AS FileName, DATALENGTH([TheFile]) AS ByteLength FROM dbo.$tableName"
                As          = "PSObject"
            }
            $row = @(Invoke-DbaQuery @splatRead)
            $row.Count | Should -Be 1
            $row[0].FileName | Should -Be (Split-Path -Path $sourceFile -Leaf)
            $row[0].ByteLength | Should -Be 64
        }
    }
}
