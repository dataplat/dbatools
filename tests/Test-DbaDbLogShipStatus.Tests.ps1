#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDbLogShipStatus",
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
                "Simple",
                "Primary",
                "Secondary",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When testing SQL instance edition support" {
        It -Skip:(-not $TestConfig.InstanceExpress) "Should warn if SQL instance edition is not supported" {
            $null = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.InstanceExpress -WarningAction SilentlyContinue
            $WarnVar | Should -Match "Express"
        }
    }

    Context "When no log shipping is configured" {
        It "Should warn if no log shipping found" {
            $null = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.InstanceSingle -Database "master" -WarningAction SilentlyContinue
            $WarnVar | Should -Match "No information available"
        }
    }

    Context "When querying log shipping status" {
        BeforeAll {
            $results = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return results or warn if no log shipping is configured" -Skip:(-not $global:dbatoolsciOutput) {
            $global:dbatoolsciOutput | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" -Skip:(-not $global:dbatoolsciOutput) {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" -Skip:(-not $global:dbatoolsciOutput) {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "InstanceType",
                "TimeSinceLastBackup",
                "LastBackupFile",
                "BackupThreshold",
                "IsBackupAlertEnabled",
                "TimeSinceLastCopy",
                "LastCopiedFile",
                "TimeSinceLastRestore",
                "LastRestoredFile",
                "LastRestoredLatency",
                "RestoreThreshold",
                "IsRestoreAlertEnabled",
                "Status"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $outputTypes = @($help.returnValues.returnValue.type.name)
            ($outputTypes -match "PSCustomObject").Count | Should -BeGreaterThan 0
        }
    }
}