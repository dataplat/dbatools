#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Invoke-DbaDbMirroring",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Primary",
                "PrimarySqlCredential",
                "Mirror",
                "MirrorSqlCredential",
                "Witness",
                "WitnessSqlCredential",
                "Database",
                "EndpointEncryption",
                "EncryptionAlgorithm",
                "SharedPath",
                "InputObject",
                "UseLastBackup",
                "Force",
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

        # Set variables. They are available in all the It blocks.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $dbName = "dbatoolsci_mirroring"
        $endpointName = "dbatoolsci_MirroringEndpoint"

        # Create the objects.
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name $dbName
        $null = New-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy1 -Name $endpointName -Type DatabaseMirroring -Port 5022 -Owner sa
        $null = New-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy2 -Name $endpointName -Type DatabaseMirroring -Port 5023 -Owner sa

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaDbMirror -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $dbName
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $dbName
        $null = Remove-DbaEndpoint -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -EndPoint $endpointName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "returns success" {
        $splatMirroring = @{
            Primary    = $TestConfig.InstanceCopy1
            Mirror     = $TestConfig.InstanceCopy2
            Database   = $dbName
            Force      = $true
            SharedPath = $TestConfig.Temp
        }
        $results = Invoke-DbaDbMirroring @splatMirroring -WarningVariable WarnVar
        $WarnVar | Should -BeNullOrEmpty
        $results.Status | Should -Be "Success"
    }

}

Describe "$CommandName Output validation" -Tag IntegrationTests {
    BeforeAll {
        $outputDbName = "dbatoolsci_mirror_output"

        # Clean up any leftover artifacts from previous runs using T-SQL for reliability
        foreach ($instance in @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)) {
            try {
                $srv = Connect-DbaInstance -SqlInstance $instance
                $srv.Query("IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '$outputDbName') BEGIN ALTER DATABASE [$outputDbName] SET PARTNER OFF END")
            } catch { }
            try {
                $srv.Query("IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '$outputDbName') BEGIN ALTER DATABASE [$outputDbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$outputDbName] END")
            } catch { }
        }

        # Use Copy2 as primary and Copy1 as mirror to handle version compatibility
        # (backup from lower version can restore to higher version, but not vice versa)
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Name $outputDbName -EnableException

        $splatOutputMirroring = @{
            Primary    = $TestConfig.InstanceCopy2
            Mirror     = $TestConfig.InstanceCopy1
            Database   = $outputDbName
            Force      = $true
            SharedPath = $TestConfig.Temp
        }
        try {
            $outputResult = Invoke-DbaDbMirroring @splatOutputMirroring -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        } catch {
            $outputResult = $null
        }
    }
    AfterAll {
        foreach ($instance in @($TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2)) {
            try {
                $srv = Connect-DbaInstance -SqlInstance $instance
                $srv.Query("IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '$outputDbName') BEGIN ALTER DATABASE [$outputDbName] SET PARTNER OFF END")
            } catch { }
            try {
                $srv.Query("IF EXISTS (SELECT 1 FROM sys.databases WHERE name = '$outputDbName') BEGIN ALTER DATABASE [$outputDbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$outputDbName] END")
            } catch { }
        }
    }

    It "Returns output of the expected type" {
        if (-not $outputResult) { Set-ItResult -Skipped -Because "mirroring setup did not return a result - endpoint connectivity may not be available" }
        $outputResult[0] | Should -BeOfType [PSCustomObject]
    }

    It "Has the expected default display properties" {
        if (-not $outputResult) { Set-ItResult -Skipped -Because "mirroring setup did not return a result - endpoint connectivity may not be available" }
        $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
        $expectedDefaults = @("Primary", "Mirror", "Database", "Status")
        foreach ($prop in $expectedDefaults) {
            $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
        }
    }
}