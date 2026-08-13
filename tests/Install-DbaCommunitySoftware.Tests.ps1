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

        It "Expands All to the six installable tools" {
            $splatAll = @{
                SqlInstance     = "NotARealInstance"
                Software        = "All"
                LocalFile       = "C:\temp\dbatoolsci_notreal.zip"
                WarningVariable = "allWarning"
                WarningAction   = "SilentlyContinue"
            }
            $null = Install-DbaCommunitySoftware @splatAll
            $allWarning | Should -Match "cannot be combined with 6 values"
            $allWarning | Should -Match "MaintenanceSolution, FirstResponderKit, DarlingData, SQLWATCH, WhoIsActive, DbaMultiTool"
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
            $multiToolServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $multiToolServer.Query("CREATE DATABASE $multiToolDb")

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

    Context "Passing a single tool straight through" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $singleToolDb = "dbatoolsci_community_$(Get-Random)"
            $singleToolServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $singleToolServer.Query("CREATE DATABASE $singleToolDb")

            $splatSingleTool = @{
                SqlInstance = $TestConfig.InstanceSingle
                Software    = "WhoIsActive"
                Database    = $singleToolDb
                Force       = $true
                Verbose     = $false
            }
            $singleToolResults = Install-DbaCommunitySoftware @splatSingleTool

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
    }

    Context "Continuing past an instance that cannot be reached" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $continueDb = "dbatoolsci_community_$(Get-Random)"
            $continueServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $continueServer.Query("CREATE DATABASE $continueDb")

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
            $whatIfServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $whatIfServer.Query("CREATE DATABASE $whatIfDb")

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
