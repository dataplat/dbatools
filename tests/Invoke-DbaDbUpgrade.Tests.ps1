#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbUpgrade",
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
                "ExcludeDatabase",
                "NoCheckDb",
                "NoUpdateUsage",
                "NoUpdateStats",
                "NoRefreshView",
                "AllUserDatabases",
                "Force",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $serverVersion = $server.VersionMajor
        # the SMO CompatibilityLevel for the server, formatted as the command reports it
        # ("Version150" -> "150").
        $serverCompat = "$($serverVersion)0"

        # One database deliberately BELOW the server level (so it gets upgraded) and one already AT
        # the server level (so it is skipped without -Force). Both get target recovery time 60 so
        # the recovery-time step is a "No change" and does not add noise. Compatibility 100 is valid
        # on every supported version (2016+).
        $random = Get-Random
        $upgradeDb = "dbatoolsci_upg_$random"
        $currentDb = "dbatoolsci_cur_$random"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $upgradeDb
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $currentDb

        $splatLower = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $upgradeDb
            Query       = "ALTER DATABASE [$upgradeDb] SET COMPATIBILITY_LEVEL = 100; ALTER DATABASE [$upgradeDb] SET TARGET_RECOVERY_TIME = 60 SECONDS;"
        }
        $null = Invoke-DbaQuery @splatLower
        $splatCurrent = @{
            SqlInstance = $TestConfig.InstanceSingle
            Database    = $currentDb
            Query       = "ALTER DATABASE [$currentDb] SET TARGET_RECOVERY_TIME = 60 SECONDS;"
        }
        $null = Invoke-DbaQuery @splatCurrent

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            $dbsToRemove = @($upgradeDb, $currentDb) | Where-Object { $PSItem }
            if ($dbsToRemove) {
                $splatRemove = @{
                    SqlInstance = $TestConfig.InstanceSingle
                    Database    = $dbsToRemove
                    ErrorAction = "SilentlyContinue"
                }
                $null = Remove-DbaDatabase @splatRemove
            }
        } finally {
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Input validation" {
        It "Warns when neither -SqlInstance nor a piped database collection is supplied" {
            # -SqlInstance is not mandatory; with nothing to connect to and nothing piped, the first
            # guard fires before any connection.
            $splatNoInstance = @{
                Database        = "dbatoolsci_none_$random"
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Invoke-DbaDbUpgrade @splatNoInstance
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 1
            $warn[0] | Should -BeLike "*You must specify either a SQL instance or pipe a database collection*"
        }

        It "Warns when no database scope is specified" {
            # -SqlInstance supplied but none of -Database/-ExcludeDatabase/-AllUserDatabases/pipe.
            $splatNoScope = @{
                SqlInstance     = $TestConfig.InstanceSingle
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Invoke-DbaDbUpgrade @splatNoScope
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 1
            $warn[0] | Should -BeLike "*You must explicitly specify a database*"
        }
    }

    Context "Upgrading compatibility" {
        It "Upgrades a below-level database and reports the compatibility change" {
            # skip the heavy DBCC/stats/refresh steps so the test is fast and focused on the
            # compatibility-level upgrade, which is the core behavior.
            $splatUpgrade = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Database      = $upgradeDb
                NoCheckDb     = $true
                NoUpdateUsage = $true
                NoUpdateStats = $true
                NoRefreshView = $true
                Confirm       = $false
            }
            $result = @(Invoke-DbaDbUpgrade @splatUpgrade)
            $result.Count | Should -Be 1
            $upgraded = $result[0]
            $upgraded.Database | Should -Be $upgradeDb
            $upgraded.OriginalCompatibility | Should -Be "100"
            $upgraded.CurrentCompatibility | Should -Be $serverCompat
            $upgraded.Compatibility | Should -Be $serverCompat
            $upgraded.TargetRecoveryTime | Should -Be "No change"
            # the explicitly skipped steps report "Skipped"
            $upgraded.UpdateUsage | Should -Be "Skipped"
            $upgraded.UpdateStats | Should -Be "Skipped"
            $upgraded.RefreshViews | Should -Be "Skipped"
            # the change actually persisted on the instance
            $liveLevel = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).Databases[$upgradeDb].CompatibilityLevel.ToString().Replace("Version", "")
            $liveLevel | Should -Be $serverCompat
        }

        It "Skips a database already at the target level when -Force is not used" {
            # levelOk and timeOk are both true, so the database is skipped and no object is emitted.
            $splatSkip = @{
                SqlInstance   = $TestConfig.InstanceSingle
                Database      = $currentDb
                NoCheckDb     = $true
                NoUpdateUsage = $true
                NoUpdateStats = $true
                NoRefreshView = $true
                Confirm       = $false
            }
            $result = Invoke-DbaDbUpgrade @splatSkip
            $result | Should -BeNullOrEmpty
        }
    }
}