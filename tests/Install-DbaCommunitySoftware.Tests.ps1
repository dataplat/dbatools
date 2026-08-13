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
            {
                Install-DbaCommunitySoftware -SqlInstance NotARealInstance -Software AzSqlTips -EnableException
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
            $results = Install-DbaCommunitySoftware @splatWarn
            $results | Should -BeNullOrEmpty
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

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Skip IntegrationTests on AppVeyor because the underlying installers fail there for unknown reasons.

    Context "Installing more than one tool in a single call" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $multiToolDb = "dbatoolsci_community_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("CREATE DATABASE $multiToolDb")

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

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $multiToolDb

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

        It "Installs every tool into the requested database: $multiToolDb" {
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
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $server.Query("CREATE DATABASE $singleToolDb")

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

            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $singleToolDb

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns the installer output unchanged" {
            $singleToolResults.Name | Should -Be "sp_WhoisActive"
            $singleToolResults.Database | Should -Be $singleToolDb
            $singleToolResults.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }

    Context "Branch and WhatIf handling" {
        It "Warns that Branch was ignored for a tool that has no branch to switch" {
            $splatNoBranch = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Software        = "WhoIsActive"
                Branch          = "main"
                WhatIf          = $true
                WarningVariable = "branchWarning"
                WarningAction   = "SilentlyContinue"
            }
            $null = Install-DbaCommunitySoftware @splatNoBranch
            $branchWarning | Should -Match "Branch was ignored for WhoIsActive"
        }

        It "Installs nothing under WhatIf" {
            $whatIfDb = "dbatoolsci_community_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
            $server.Query("CREATE DATABASE $whatIfDb")

            try {
                $splatWhatIf = @{
                    SqlInstance = $TestConfig.InstanceSingle
                    Software    = "WhoIsActive"
                    Database    = $whatIfDb
                    WhatIf      = $true
                }
                $null = Install-DbaCommunitySoftware @splatWhatIf

                # A freshly created database has no user procedures at all, so any row here
                # means WhatIf let the install through.
                $procedureCount = $server.Query("SELECT COUNT(*) AS ProcCount FROM $whatIfDb.sys.procedures")
                $procedureCount.ProcCount | Should -Be 0
            } finally {
                Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $whatIfDb -EnableException
            }
        }
    }
}
