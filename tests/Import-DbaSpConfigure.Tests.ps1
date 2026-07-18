#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaSpConfigure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "SqlInstance",
                "Path",
                "SqlCredential",
                "Force",
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

        $random = Get-Random
        $exportDir = Join-Path -Path $TestConfig.Temp -ChildPath "dbatoolsci_impspcfg_$random"
        $splatNewDir = @{
            ItemType = "Directory"
            Force    = $true
            Path     = $exportDir
        }
        $null = New-Item @splatNewDir

        # Export the instance's CURRENT sp_configure settings so the import round-trip re-applies
        # the exact same values - a net-neutral change safe to run against a live instance.
        $configFile = Join-Path -Path $exportDir -ChildPath "spcfg_$random.sql"
        $null = Export-DbaSpConfigure -SqlInstance $TestConfig.InstanceSingle -FilePath $configFile

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $splatCleanupDir = @{
            Path        = $exportDir
            Recurse     = $true
            Force       = $true
            ErrorAction = "SilentlyContinue"
        }
        Remove-Item @splatCleanupDir
    }

    Context "Importing from a file" {
        It "Warns and returns nothing when -Path does not exist" {
            # sysadmin is checked first (passes on the lab), then the missing file is rejected
            # before anything is applied.
            $missingPath = Join-Path -Path $exportDir -ChildPath "does_not_exist_$random.sql"
            $splatMissing = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $missingPath
                Confirm         = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaSpConfigure @splatMissing
            $result | Should -BeNullOrEmpty
            $warn -join " " | Should -Match "File .* Not Found"
        }

        It "Applies the file and returns no pipeline object despite the .OUTPUTS Boolean doc" {
            $splatImport = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $configFile
                Confirm         = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaSpConfigure @splatImport
            # characterization: .OUTPUTS documents System.Boolean, but the command only writes
            # messages and emits NOTHING to the pipeline.
            $result | Should -BeNullOrEmpty
            # the FromFile success path always warns that a restart may be required
            $warn -join " " | Should -Match "updated once SQL Server is restarted"
        }

        It "Does not import or warn about a restart under -WhatIf" {
            # The entire import block sits inside ShouldProcess, so -WhatIf runs no queries and the
            # restart warning (also inside the block) is never emitted.
            $splatWhatIf = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Path            = $configFile
                WhatIf          = $true
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $result = Import-DbaSpConfigure @splatWhatIf
            $result | Should -BeNullOrEmpty
            $warn -join " " | Should -Not -Match "updated once SQL Server is restarted"
        }
    }

    # NOTE: the ServerCopy parameter set (-Source/-Destination) is intentionally not covered here.
    # It migrates configuration between two live instances and its version-mismatch guard compares
    # source vs destination major versions - both require a SECOND distinct instance, which this
    # feeder's single-instance (InstanceSingle) lab does not provide. DEFERRED-TO-GATE for an
    # integrator with a two-instance lab.
}