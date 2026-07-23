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
            # exactly one success object comes back (duplicate output would otherwise slip through)
            $result = @(Import-DbaBinaryFile @splatImport)
            $result.Count | Should -Be 1
            $imported = $result[0]
            $imported | Should -BeOfType System.Management.Automation.PSCustomObject
            $imported.Status | Should -Be "Success"
            $imported.Database | Should -Be $db
            $imported.Table | Should -Be $tableName
            $imported.FilePath | Should -Be $sourceFile
            # identity columns carry the connected server's values, not just any non-null string
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $imported.ComputerName | Should -Be $server.ComputerName
            $imported.InstanceName | Should -Be $server.ServiceName
            $imported.SqlInstance | Should -Be $server.DomainInstanceName

            # the row landed with the leaf filename and the EXACT payload bytes: comparing the
            # SHA-256 of the stored varbinary to the source file hash catches corrupted or wrong
            # content that a length-only check would miss. [char]39 supplies the single quotes the
            # T-SQL literal needs without putting forbidden single quotes in the test source.
            $q = [char]39
            $splatRead = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $db
                Query       = "SELECT [FileName] AS FileName, DATALENGTH([TheFile]) AS ByteLength, CONVERT(CHAR(64), HASHBYTES(${q}SHA2_256${q}, [TheFile]), 2) AS Sha FROM dbo.$tableName"
                As          = "PSObject"
            }
            $rows = @(Invoke-DbaQuery @splatRead)
            $rows.Count | Should -Be 1
            $rows[0].FileName | Should -Be (Split-Path -Path $sourceFile -Leaf)
            $rows[0].ByteLength | Should -Be 64
            $rows[0].Sha | Should -Be (Get-FileHash -Path $sourceFile -Algorithm SHA256).Hash
        }
    }

    Context "Cross-record statement persistence on a multi-table pipe" {
        # $Statement and the auto-detected $FileNameColumn/$BinaryColumn are NON-pipeline parameters
        # that the process block reassigns. PowerShell keeps a reassigned non-pipeline parameter value
        # across process iterations, so once the FIRST piped table builds its INSERT the value persists
        # to every later piped table and the if (-not $Statement) build block is skipped. The command
        # therefore reuses the first table's INSERT for the rest of the pipe: the file lands in the
        # first table again instead of the second. This pins that behavior so a rewrite cannot silently
        # change it.
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $firstTable = "CarryFirst"
            $secondTable = "CarrySecond"
            $splatTwoTables = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $db
                Query       = "CREATE TABLE dbo.$firstTable ([FileName] NVARCHAR(500) NULL, [TheFile] VARBINARY(MAX) NULL); CREATE TABLE dbo.$secondTable ([FileName] NVARCHAR(500) NULL, [TheFile] VARBINARY(MAX) NULL)"
            }
            $null = Invoke-DbaQuery @splatTwoTables
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Reuses the first piped table's INSERT for later tables, so the file lands in the first table twice" {
            # Fetch the two tables and pipe them in a fixed order so the first record is deterministic,
            # then import one file. Faithful behavior: both records reuse the first table's INSERT, so
            # the first table receives two rows and the second receives none.
            $tableOne = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $db -Table $firstTable
            $tableTwo = Get-DbaDbTable -SqlInstance $TestConfig.InstanceSingle -Database $db -Table $secondTable
            $result = @($tableOne, $tableTwo | Import-DbaBinaryFile -FilePath $sourceFile -Confirm:$false)
            $result.Count | Should -Be 2

            $splatCount = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $db
                As          = "PSObject"
            }
            $firstCount = (Invoke-DbaQuery @splatCount -Query "SELECT COUNT(*) AS Total FROM dbo.$firstTable").Total
            $secondCount = (Invoke-DbaQuery @splatCount -Query "SELECT COUNT(*) AS Total FROM dbo.$secondTable").Total
            $firstCount | Should -Be 2
            $secondCount | Should -Be 0
        }
    }
}
