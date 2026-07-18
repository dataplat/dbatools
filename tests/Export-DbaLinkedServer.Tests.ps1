#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
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

    Context "Decryption behavior" -Skip:($IsLinux -or $IsMacOS) {
        BeforeAll {
            Mock Test-ExportDirectory { } -ModuleName dbatools
            Mock Test-FunctionInterrupt { $false } -ModuleName dbatools
            Mock Connect-DbaInstance {
                $mockLinkedServer = New-Object Microsoft.SqlServer.Management.Smo.LinkedServer
                $mockLinkedServer.Name = "linked1"
                $mockLinkedServer | Add-Member -MemberType ScriptMethod -Name Script -Value {
                    "EXEC sp_addlinkedserver @server=N'linked1'"
                } -Force

                $server = New-Object Microsoft.SqlServer.Management.Smo.Server "sql1"
                $server | Add-Member -MemberType NoteProperty -Name LinkedServers -Value @($mockLinkedServer) -Force
                $server
            } -ModuleName dbatools
            Mock Disconnect-DbaInstance { } -ModuleName dbatools
            Mock Get-ExportFilePath { "C:\temp\linkedservers.sql" } -ModuleName dbatools
            Mock Get-DecryptedObject {
                [PSCustomObject]@{
                    Name     = "linked1"
                    Identity = "remoteuser"
                    Password = "Password1!"
                }
            } -ModuleName dbatools
        }

        It "Should not force decryption errors to throw by default" {
            $null = Export-DbaLinkedServer -SqlInstance "sql1" -Passthru

            Assert-MockCalled -CommandName Get-DecryptedObject -Exactly 1 -Scope It -ModuleName dbatools -ParameterFilter {
                -not $EnableException
            }
        }

        It "Should request terminating decryption errors when EnableException is specified" {
            $null = Export-DbaLinkedServer -SqlInstance "sql1" -Passthru -EnableException

            Assert-MockCalled -CommandName Get-DecryptedObject -Exactly 1 -Scope It -ModuleName dbatools -ParameterFilter {
                $EnableException
            }
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    Context "Exporting a live linked server" -Skip:($IsLinux -or $IsMacOS) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Fabricated provider/data source - New-DbaLinkedServer registers the linked server
            # without contacting any remote, so no external dependency is required. No login
            # mapping is added, which keeps every assertion on the DAC-free -ExcludePassword path
            # (the password-decryption path needs a dedicated admin connection and a remote login).
            $random = Get-Random
            $ls1 = "dbatoolsci_els1_$random"
            $ls2 = "dbatoolsci_els2_$random"

            # Create the export directory FIRST so $exportDir is always assigned before anything
            # that can throw - otherwise a failed linked-server creation would leave AfterAll with
            # a null path and cleanup would fail even under SilentlyContinue.
            $exportDir = Join-Path -Path $TestConfig.Temp -ChildPath "dbatoolsci_els_$random"
            $splatNewDir = @{
                ItemType = "Directory"
                Force    = $true
                Path     = $exportDir
            }
            $null = New-Item @splatNewDir

            # Fabricated provider/data source - New-DbaLinkedServer registers the linked server
            # without contacting any remote, so no external dependency is required. No login
            # mapping is added, which keeps every assertion on the DAC-free -ExcludePassword path
            # (the password-decryption path needs a dedicated admin connection and a remote login).
            $splatLs1 = @{
                SqlInstance   = $TestConfig.InstanceSingle
                LinkedServer  = $ls1
                ServerProduct = "product1"
                Provider      = "SQLNCLI"
                DataSource    = "dbatoolsci_src1"
            }
            $null = New-DbaLinkedServer @splatLs1
            $splatLs2 = @{
                SqlInstance   = $TestConfig.InstanceSingle
                LinkedServer  = $ls2
                ServerProduct = "product2"
                Provider      = "SQLNCLI"
                DataSource    = "dbatoolsci_src2"
            }
            $null = New-DbaLinkedServer @splatLs2

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            try {
                # Pipe only the linked servers that actually exist so a partial BeforeAll never
                # makes cleanup throw under the forced EnableException and skip the rest.
                $splatGet = @{
                    SqlInstance  = $TestConfig.InstanceSingle
                    LinkedServer = @($ls1, $ls2)
                    ErrorAction  = "SilentlyContinue"
                }
                Get-DbaLinkedServer @splatGet | Remove-DbaLinkedServer -Force -ErrorAction SilentlyContinue
                $splatCleanupDir = @{
                    Path        = $exportDir
                    Recurse     = $true
                    Force       = $true
                    ErrorAction = "SilentlyContinue"
                }
                Remove-Item @splatCleanupDir
            } finally {
                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }
        }

        It "Returns the T-SQL script as a string under -Passthru" {
            $splatPass = @{
                SqlInstance     = $TestConfig.InstanceSingle
                LinkedServer    = $ls1
                ExcludePassword = $true
                Passthru        = $true
            }
            $result = Export-DbaLinkedServer @splatPass
            $result | Should -Not -BeNullOrEmpty
            # -Passthru returns the raw T-SQL script - every emitted item is a string
            $result | ForEach-Object { $PSItem | Should -BeOfType System.String }
            $joined = $result -join [Environment]::NewLine
            $joined | Should -Match "sp_addlinkedserver"
            $joined | Should -Match $ls1
        }

        It "Writes the script to the requested -FilePath and returns the FileInfo" {
            $filePath = Join-Path -Path $exportDir -ChildPath "els_filepath_$random.sql"
            $splatFile = @{
                SqlInstance     = $TestConfig.InstanceSingle
                LinkedServer    = $ls1
                ExcludePassword = $true
                FilePath        = $filePath
            }
            $result = Export-DbaLinkedServer @splatFile
            $result | Should -BeOfType System.IO.FileInfo
            $result.FullName | Should -Be $filePath
            Test-Path -Path $filePath | Should -BeTrue
            (Get-Content -Path $filePath -Raw) | Should -Match $ls1
        }

        It "Auto-generates a .sql file name under -Path" {
            $splatPath = @{
                SqlInstance     = $TestConfig.InstanceSingle
                LinkedServer    = $ls1
                ExcludePassword = $true
                Path            = $exportDir
            }
            $result = Export-DbaLinkedServer @splatPath
            $result | Should -BeOfType System.IO.FileInfo
            $result.Extension | Should -Be ".sql"
            $result.DirectoryName | Should -Be $exportDir
            # Get-ExportFilePath builds "<server>-<timestamp>-<caller>.sql": the server prefix is
            # the instance name with backslash replaced by "$", the caller token resolves to
            # "linkedserver" (Export-Dba stripped and lowercased), and a timestamp sits between.
            $serverToken = [regex]::Escape($TestConfig.InstanceSingle.ToString().Replace([char]92, [char]36))
            $result.Name | Should -Match "^$serverToken-.+-linkedserver\.sql$"
            (Get-Content -Path $result.FullName -Raw) | Should -Match $ls1
        }

        It "Writes to the configured export directory when no -Path, -FilePath, or -Passthru is given" {
            # -Path carries a config default (Path.DbatoolsExport), so a file is always written
            # even with none of the output switches supplied, and the FileInfo is returned. Point
            # the config at the unique test directory so the file lands there (cleaned by AfterAll)
            # instead of leaking into the shared default export location on an assertion failure.
            $originalExportPath = Get-DbatoolsConfigValue -FullName "Path.DbatoolsExport"
            try {
                Set-DbatoolsConfig -FullName "Path.DbatoolsExport" -Value $exportDir
                $splatDefault = @{
                    SqlInstance     = $TestConfig.InstanceSingle
                    LinkedServer    = $ls1
                    ExcludePassword = $true
                }
                $result = Export-DbaLinkedServer @splatDefault
                $result | Should -BeOfType System.IO.FileInfo
                $result.Extension | Should -Be ".sql"
                $result.DirectoryName | Should -Be $exportDir
                Test-Path -Path $result.FullName | Should -BeTrue
            } finally {
                Set-DbatoolsConfig -FullName "Path.DbatoolsExport" -Value $originalExportPath
            }
        }

        It "Filters to the requested linked server with -LinkedServer" {
            $splatFilter = @{
                SqlInstance     = $TestConfig.InstanceSingle
                LinkedServer    = $ls1
                ExcludePassword = $true
                Passthru        = $true
            }
            $joined = (Export-DbaLinkedServer @splatFilter) -join [Environment]::NewLine
            $joined | Should -Match $ls1
            $joined | Should -Not -Match $ls2
        }

        It "Overwrites without -Append and preserves prior content with -Append" {
            # Preseed a sentinel so the two branches are distinguishable: an implementation that
            # always appended would leave the sentinel after the non-Append write and pass a
            # both-present-only assertion. The non-Append call must REMOVE the sentinel.
            $appendPath = Join-Path -Path $exportDir -ChildPath "els_append_$random.sql"
            $sentinel = "dbatoolsci_sentinel_$random"
            Set-Content -Path $appendPath -Value $sentinel

            $splatFirst = @{
                SqlInstance     = $TestConfig.InstanceSingle
                LinkedServer    = $ls1
                ExcludePassword = $true
                FilePath        = $appendPath
            }
            $null = Export-DbaLinkedServer @splatFirst
            $afterOverwrite = Get-Content -Path $appendPath -Raw
            $afterOverwrite | Should -Not -Match $sentinel
            $afterOverwrite | Should -Match $ls1

            $splatAppend = @{
                SqlInstance     = $TestConfig.InstanceSingle
                LinkedServer    = $ls2
                ExcludePassword = $true
                FilePath        = $appendPath
                Append          = $true
            }
            $null = Export-DbaLinkedServer @splatAppend
            $afterAppend = Get-Content -Path $appendPath -Raw
            $afterAppend | Should -Match $ls1
            $afterAppend | Should -Match $ls2
        }

        It "Exports all linked servers when -LinkedServer is omitted" {
            # Omitting -LinkedServer selects every linked server on the instance, so both fixtures
            # must appear (other pre-existing linked servers may also be present - not asserted).
            $splatAllLs = @{
                SqlInstance     = $TestConfig.InstanceSingle
                ExcludePassword = $true
                Passthru        = $true
            }
            $joined = (Export-DbaLinkedServer @splatAllLs) -join [Environment]::NewLine
            $joined | Should -Match $ls1
            $joined | Should -Match $ls2
        }

        It "Processes every value supplied to -SqlInstance" {
            # Passing the same instance twice exercises the foreach($instance in $SqlInstance) loop
            # without needing a second lab instance: an implementation that handled only the first
            # element would script the linked server once instead of twice. sp_addlinkedserver is
            # emitted once per linked server per instance (no login mapping, so no sp_addlinkedsrvlogin).
            $splatMulti = @{
                SqlInstance     = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle)
                LinkedServer    = $ls1
                ExcludePassword = $true
                Passthru        = $true
            }
            $joined = (Export-DbaLinkedServer @splatMulti) -join [Environment]::NewLine
            ([regex]::Matches($joined, "sp_addlinkedserver")).Count | Should -Be 2
        }

        It "Exports nothing and reports Nothing to export when the named linked server does not exist" {
            $splatMissing = @{
                SqlInstance     = $TestConfig.InstanceSingle
                LinkedServer    = "dbatoolsci_nols_$random"
                ExcludePassword = $true
                Passthru        = $true
                Verbose         = $true
            }
            # capture the verbose stream (4) alongside output so both the empty result and the
            # documented "Nothing to export" message are pinned.
            $captured = Export-DbaLinkedServer @splatMissing 4>&1
            $emitted = $captured | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }
            $verbose = $captured | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] }
            $emitted | Should -BeNullOrEmpty
            ($verbose.Message -join " ") | Should -Match "Nothing to export"
        }
    }

    Context "Platform guard" -Skip:(-not ($IsLinux -or $IsMacOS)) {
        It "Warns and returns nothing on Linux or macOS" {
            # The OS guard fires before any connection attempt, so this needs no live instance.
            $splatGuard = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Passthru        = $true
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            $result = Export-DbaLinkedServer @splatGuard
            $result | Should -BeNullOrEmpty
            $warn -join " " | Should -Match "not supported on Linux or macOS"
        }
    }
}
