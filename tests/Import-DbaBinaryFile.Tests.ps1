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
        # -SqlInstance is deliberately omitted from every guard case: it is not mandatory, and each
        # guard Stop-Functions before any Get-DbaDbTable connection - so a warning WITHOUT a
        # connection attempt proves the validation is genuinely pre-connection. Each case asserts a
        # single warning carrying the complete expected message.
        It "Warns when neither Database and Table nor a piped table is supplied" {
            $splatNoTable = @{
                Database        = $db
                Path            = $sourceDir
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaBinaryFile @splatNoTable
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 1
            $warn[0] | Should -BeLike "*You must specify either Database and Table or pipe in a table*"
        }

        It "Warns when both -Path and -FilePath are supplied" {
            $splatBoth = @{
                Database        = $db
                Table           = $tableName
                Path            = $sourceDir
                FilePath        = $sourceFile
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaBinaryFile @splatBoth
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 1
            $warn[0] | Should -BeLike "*You cannot specify both -Path and -FilePath*"
        }

        It "Warns when neither -Path nor -FilePath is supplied" {
            $splatNeither = @{
                Database        = $db
                Table           = $tableName
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaBinaryFile @splatNeither
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 1
            # characterization: the message keeps the source grammar quirk ("either" means "neither")
            $warn[0] | Should -BeLike "*You cannot specify either -Path or -FilePath*"
        }

        It "Warns for a nonexistent -Path with the exact path" {
            $missingDir = Join-Path -Path $sourceDir -ChildPath "missing_dir_$random"
            $splatBadPath = @{
                Database        = $db
                Table           = $tableName
                Path            = $missingDir
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaBinaryFile @splatBadPath
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 1
            $warn[0] | Should -BeLike "*Path $missingDir does not exist*"
        }

        It "Warns for a nonexistent -FilePath with the exact path" {
            $missingFile = Join-Path -Path $sourceDir -ChildPath "does_not_exist_$random.bin"
            $splatMissing = @{
                Database        = $db
                Table           = $tableName
                FilePath        = $missingFile
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaBinaryFile @splatMissing
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 1
            $warn[0] | Should -BeLike "*File $missingFile does not exist*"
        }

        It "Warns when -FilePath points at a directory" {
            $splatDir = @{
                Database        = $db
                Table           = $tableName
                FilePath        = $sourceDir
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaBinaryFile @splatDir
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 1
            $warn[0] | Should -BeLike "*FilePath must be one or more files, not a directory*"
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
            $result | Should -BeOfType System.Management.Automation.PSCustomObject
            $result.Status | Should -Be "Success"
            $result.Database | Should -Be $db
            $result.Table | Should -Be $tableName
            $result.FilePath | Should -Be $sourceFile
            # identity columns carry the connected server's values, not just any non-null string
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $result.ComputerName | Should -Be $server.ComputerName
            $result.InstanceName | Should -Be $server.ServiceName
            $result.SqlInstance | Should -Be $server.DomainInstanceName

            # the row actually landed: the filename column holds the leaf name and the binary column
            # holds all 64 payload bytes (auto-detected FileName + TheFile columns).
            $splatRead = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $db
                Query       = "SELECT [FileName] AS FileName, DATALENGTH([TheFile]) AS ByteLength FROM dbo.$tableName"
                As          = "PSObject"
            }
            $rows = @(Invoke-DbaQuery @splatRead)
            $rows.Count | Should -Be 1
            $rows[0].FileName | Should -Be (Split-Path -Path $sourceFile -Leaf)
            $rows[0].ByteLength | Should -Be 64
        }
    }
}
