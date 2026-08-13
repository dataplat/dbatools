#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Install-DbaCommunitySoftware",
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
                "Software",
                "Database",
                "Branch",
                "LocalFile",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should reject a software name that has no installer" {
            # AzSqlTips is downloadable through Save-DbaCommunitySoftware but is queried by
            # Invoke-DbaDbAzSqlTip rather than installed, so it is deliberately out of the set.
            $splatBadSoftware = @{
                SqlInstance     = "NotARealInstance"
                Software        = "AzSqlTips"
                EnableException = $true
            }
            {
                Install-DbaCommunitySoftware @splatBadSoftware
            } | Should -Throw
        }

        It "Rejects an empty database name" {
            # An empty value would reach Install-DbaWhoIsActive's own "-not $Database" test and
            # open its interactive picker, which would hang an unattended run.
            $splatEmptyDatabase = @{
                SqlInstance     = "NotARealInstance"
                Software        = "WhoIsActive"
                Database        = ""
                EnableException = $true
            }
            {
                Install-DbaCommunitySoftware @splatEmptyDatabase
            } | Should -Throw
        }

        It "Rejects a whitespace database name" {
            # ValidateNotNullOrEmpty lets whitespace through, so this reaches the command's own
            # guard rather than the attribute, and the message proves which one caught it.
            $splatWhitespaceDatabase = @{
                SqlInstance     = "NotARealInstance"
                Software        = "WhoIsActive"
                Database        = "   "
                EnableException = $true
            }
            {
                Install-DbaCommunitySoftware @splatWhitespaceDatabase
            } | Should -Throw -ExpectedMessage "*Database is only whitespace*"
        }
    }

    Context "LocalFile guard" {
        # These run before any connection or download is attempted, so they need no instance.

        It "Throws when LocalFile is combined with more than one tool" {
            $splatMultiple = @{
                SqlInstance     = "NotARealInstance"
                Software        = "FirstResponderKit", "WhoIsActive"
                LocalFile       = "C:\temp\dbatoolsci_notreal.zip"
                EnableException = $true
            }
            {
                Install-DbaCommunitySoftware @splatMultiple
            } | Should -Throw -ExpectedMessage "*cannot be combined with 2 values*"
        }

        It "Warns instead of throwing when EnableException is not used" {
            $splatWarn = @{
                SqlInstance     = "NotARealInstance"
                Software        = "FirstResponderKit", "WhoIsActive"
                LocalFile       = "C:\temp\dbatoolsci_notreal.zip"
                WarningVariable = "localFileWarning"
                WarningAction   = "SilentlyContinue"
            }
            $localFileResults = Install-DbaCommunitySoftware @splatWarn
            $localFileResults | Should -BeNullOrEmpty
            $localFileWarning | Should -Match "cannot be combined with 2 values"
        }

        It "Expands All to every installable tool" {
            $splatAll = @{
                SqlInstance     = "NotARealInstance"
                Software        = "All"
                LocalFile       = "C:\temp\dbatoolsci_notreal.zip"
                WarningVariable = "allWarning"
                WarningAction   = "SilentlyContinue"
            }
            $null = Install-DbaCommunitySoftware @splatAll

            # Two warnings can land here on Core, so join them rather than matching a collection.
            $allWarningText = $allWarning -join " "

            if ($PSEdition -eq "Core") {
                # SQLWATCH is dropped before the LocalFile guard is reached, so All is five here.
                $allWarningText | Should -Match "cannot be combined with 5 values"
                $allWarningText | Should -Match "MaintenanceSolution, FirstResponderKit, DarlingData, WhoIsActive, DbaMultiTool"
            } else {
                $allWarningText | Should -Match "cannot be combined with 6 values"
                $allWarningText | Should -Match "MaintenanceSolution, FirstResponderKit, DarlingData, SQLWATCH, WhoIsActive, DbaMultiTool"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:([bool]$env:appveyor) {
    # Skip IntegrationTests on AppVeyor because the underlying installers fail there for unknown reasons.

    Context "Installing more than one tool in a single call" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $multiToolDb = "dbatoolsci_community_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $multiToolDb

            $splatMultiTool = @{
                SqlInstance = $TestConfig.InstanceSingle
                Software    = "FirstResponderKit", "DarlingData"
                Database    = $multiToolDb
                Force       = $true
                Verbose     = $false
            }
            $multiToolResults = Install-DbaCommunitySoftware @splatMultiTool

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatCleanupMultiTool = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $multiToolDb
                ErrorAction = "SilentlyContinue"
            }
            Remove-DbaDatabase @splatCleanupMultiTool

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns rows from the First Responder Kit" {
            @($multiToolResults.Name -match "sp_Blitz").Count | Should -BeGreaterThan 0
        }

        It "Returns rows from DarlingData in the same call" {
            # DarlingData installs from one combined script, so it emits a single row named
            # for the kit rather than one row per procedure the way the other tools do.
            @($multiToolResults.Name -eq "DarlingData").Count | Should -Be 1
        }

        It "Installs every tool into the requested database" {
            @($multiToolResults.Database | Select-Object -Unique) | Should -Be $multiToolDb
        }

        It "Reports no failures" {
            @($multiToolResults | Where-Object Status -eq "Error") | Should -BeNullOrEmpty
        }
    }

    Context "Handing the whole instance list to each installer" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $multiInstanceDb = "dbatoolsci_community_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $multiInstanceDb
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $multiInstanceDb

            $splatMultiInstance = @{
                SqlInstance = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
                Software    = "WhoIsActive"
                Database    = $multiInstanceDb
                Force       = $true
            }
            # Verbose is captured rather than silenced here: the dispatch message is the only
            # observable proof that the installer was entered once instead of once per instance.
            $multiInstanceStreams = Install-DbaCommunitySoftware @splatMultiInstance -Verbose 4>&1
            $multiInstanceDispatch = @($multiInstanceStreams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -match "Installing WhoIsActive on" })
            $multiInstanceResults = @($multiInstanceStreams | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $multiInstanceDb -ErrorAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Database $multiInstanceDb -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Enters the installer once no matter how many instances are targeted" {
            # Every installer downloads in begin, so a second entry would mean a second download.
            $multiInstanceDispatch.Count | Should -Be 1
        }

        It "Installs on both instances from that one call" {
            $multiInstanceResults.Count | Should -Be 2
            @($multiInstanceResults.SqlInstance | Select-Object -Unique).Count | Should -Be 2
            @($multiInstanceResults.Name | Select-Object -Unique) | Should -Be "sp_WhoisActive"
        }
    }

    Context "Passing a single tool straight through" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $singleToolDb = "dbatoolsci_community_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $singleToolDb

            $splatSingleTool = @{
                SqlInstance = $TestConfig.InstanceSingle
                Software    = "WhoIsActive"
                Database    = $singleToolDb
                Force       = $true
                Verbose     = $false
            }
            $singleToolResults = Install-DbaCommunitySoftware @splatSingleTool

            $splatMixedCase = @{
                SqlInstance = $TestConfig.InstanceSingle
                Software    = "WhoIsActive", "whoisactive"
                Database    = $singleToolDb
                Force       = $true
                Verbose     = $false
            }
            $mixedCaseResults = Install-DbaCommunitySoftware @splatMixedCase

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatCleanupSingleTool = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $singleToolDb
                ErrorAction = "SilentlyContinue"
            }
            Remove-DbaDatabase @splatCleanupSingleTool

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns the installer output unchanged" {
            $singleToolResults.Name | Should -Be "sp_WhoisActive"
            $singleToolResults.Database | Should -Be $singleToolDb
            $singleToolResults.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Runs a differently cased duplicate only once" {
            # ValidateSet accepts any casing, so the deduplication has to be case-insensitive
            # or the same installer runs twice against the same database.
            @($mixedCaseResults).Count | Should -Be 1
        }
    }

    Context "Defaulting WhoIsActive to master when Database is omitted" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $defaultServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $masterDatabase = $defaultServer.Databases["master"]

            # The install replaces dbo.sp_WhoisActive in place, and a copy already sitting in master
            # may be someone's own. Its full state cannot be put back afterwards - an encrypted
            # procedure has no recoverable definition, and permissions granted on it do not survive
            # a drop - so leave it alone entirely and skip instead. The schema has to be part of the
            # lookup: a procedure of the same name under another schema is not the one we overwrite.
            $whoIsActivePreExisted = [bool]$masterDatabase.StoredProcedures["sp_WhoisActive", "dbo"]

            $defaultDatabaseResults = $null
            if (-not $whoIsActivePreExisted) {
                $splatDefaultDatabase = @{
                    SqlInstance = $TestConfig.InstanceSingle
                    Software    = "WhoIsActive"
                    Force       = $true
                    Verbose     = $false
                }
                $defaultDatabaseResults = Install-DbaCommunitySoftware @splatDefaultDatabase
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Only ever remove a procedure this test created. Dropped through SMO rather than
            # DROP PROCEDURE IF EXISTS, which needs SQL Server 2016.
            if (-not $whoIsActivePreExisted) {
                $masterDatabase.StoredProcedures.Refresh()
                $installedWhoIsActive = $masterDatabase.StoredProcedures["sp_WhoisActive", "dbo"]
                if ($installedWhoIsActive) {
                    $installedWhoIsActive.Drop()
                }
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Installs into master rather than stalling on the interactive picker" {
            if ($whoIsActivePreExisted) {
                Set-ItResult -Skipped -Because "master.dbo.sp_WhoisActive already exists and this test will not overwrite an object it did not create"
                return
            }
            $defaultDatabaseResults.Database | Should -Be "master"
            $defaultDatabaseResults.Name | Should -Be "sp_WhoisActive"
        }
    }

    Context "Skipping SQLWATCH on PowerShell Core" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $coreSkipDb = "dbatoolsci_community_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $coreSkipDb

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # Save-DbaCommunitySoftware deletes and recreates this directory every time it runs,
            # so its write time is the sentinel for whether SqlWatch downloaded anything. Force
            # below makes Install-DbaSqlWatch refresh it unconditionally, so an unchanged
            # timestamp - or a directory that still does not exist - can only mean the installer
            # was never entered.
            $sqlWatchCachePath = Join-Path -Path (Get-DbatoolsConfigValue -FullName "Path.DbatoolsData") -ChildPath "SQLWATCH"
            $sqlWatchCacheBefore = Get-Item -Path $sqlWatchCachePath -ErrorAction SilentlyContinue

            # Only run the call on Core. Under Windows PowerShell this would start a real SqlWatch
            # DACPAC deployment, which is far heavier than anything else in this file.
            $coreSkipResults = $null
            $sqlWatchCacheAfter = $null
            if ($PSEdition -eq "Core") {
                $splatCoreSkip = @{
                    SqlInstance     = $TestConfig.InstanceSingle
                    Software        = "SQLWATCH", "WhoIsActive"
                    Database        = $coreSkipDb
                    Force           = $true
                    WarningVariable = "coreSkipWarning"
                    WarningAction   = "SilentlyContinue"
                }
                $coreSkipResults = Install-DbaCommunitySoftware @splatCoreSkip
                $sqlWatchCacheAfter = Get-Item -Path $sqlWatchCachePath -ErrorAction SilentlyContinue
            }
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatCleanupCoreSkip = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $coreSkipDb
                ErrorAction = "SilentlyContinue"
            }
            Remove-DbaDatabase @splatCleanupCoreSkip

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Warns that SQLWATCH needs Windows PowerShell" -Skip:($PSEdition -ne "Core") {
            $coreSkipWarning | Should -Match "SQLWATCH was skipped"
        }

        It "Installs the supported tools in the same call" -Skip:($PSEdition -ne "Core") {
            @($coreSkipResults).Count | Should -Be 1
            $coreSkipResults.Name | Should -Be "sp_WhoisActive"
        }

        It "Never enters the SqlWatch installer at all" -Skip:($PSEdition -ne "Core") {
            # Install-DbaSqlWatch downloads in begin and only then hits its own Core check, so
            # its refusal message appearing would mean the download had already happened.
            $coreSkipWarning | Should -Not -Match "PowerShell Core is not supported"

            # The absent message alone would also fit a download that failed before warning, so
            # check the cache itself. Compare write times rather than creation times: Windows
            # file system tunneling can carry a creation time onto a recreated directory.
            if ($null -eq $sqlWatchCacheBefore) {
                $sqlWatchCacheAfter | Should -BeNullOrEmpty
            } else {
                $sqlWatchCacheAfter.LastWriteTime | Should -Be $sqlWatchCacheBefore.LastWriteTime
            }
        }
    }

    Context "Continuing past an instance that cannot be reached" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $continueDb = "dbatoolsci_community_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $continueDb

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The unreachable host goes first on purpose: it must fail before the real
            # instance is reached, so a row back from the real one proves the batch continued.
            $splatContinue = @{
                SqlInstance   = "dbatoolsci_no_such_host", $TestConfig.InstanceSingle
                Software      = "WhoIsActive"
                Database      = $continueDb
                WarningAction = "SilentlyContinue"
            }
            $continueResults = Install-DbaCommunitySoftware @splatContinue
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatCleanupContinue = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $continueDb
                ErrorAction = "SilentlyContinue"
            }
            Remove-DbaDatabase @splatCleanupContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Still installs on the instance that follows the failure" {
            @($continueResults).Count | Should -Be 1
            $continueResults.Database | Should -Be $continueDb
        }

        It "Reports no row for the instance that failed" {
            @($continueResults.SqlInstance) | Should -Not -Contain "dbatoolsci_no_such_host"
        }

        It "Throws on the first failure when EnableException is used" {
            $splatContinueException = @{
                SqlInstance     = "dbatoolsci_no_such_host", $TestConfig.InstanceSingle
                Software        = "WhoIsActive"
                Database        = $continueDb
                EnableException = $true
            }
            {
                Install-DbaCommunitySoftware @splatContinueException
            } | Should -Throw
        }
    }

    Context "Branch and WhatIf handling" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $whatIfDb = "dbatoolsci_community_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $whatIfDb
            $whatIfServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatNoBranch = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Software        = "WhoIsActive"
                Branch          = "main"
                WhatIf          = $true
                WarningVariable = "branchWarning"
                WarningAction   = "SilentlyContinue"
            }
            $null = Install-DbaCommunitySoftware @splatNoBranch

            $splatWhatIf = @{
                SqlInstance = $TestConfig.InstanceSingle
                Software    = "WhoIsActive"
                Database    = $whatIfDb
                WhatIf      = $true
            }
            $null = Install-DbaCommunitySoftware @splatWhatIf

            # A freshly created database has no user procedures at all, so any row here
            # means WhatIf let the install through.
            $whatIfProcedures = $whatIfServer.Query("SELECT COUNT(*) AS ProcCount FROM $whatIfDb.sys.procedures")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatCleanupWhatIf = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $whatIfDb
                ErrorAction = "SilentlyContinue"
            }
            Remove-DbaDatabase @splatCleanupWhatIf

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Warns that Branch was ignored for a tool that has no branch to switch" {
            $branchWarning | Should -Match "Branch was ignored for WhoIsActive"
        }

        It "Installs nothing under WhatIf" {
            $whatIfProcedures.ProcCount | Should -Be 0
        }
    }
}
