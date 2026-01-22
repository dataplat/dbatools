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
            $null = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.InstanceSingle -Database 'master' -WarningAction SilentlyContinue
            $WarnVar | Should -Match "No information available"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            # Skip if no log shipping configured or Express edition
            $hasLogShipping = $false
            try {
                $testResult = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.instance2 -EnableException -WarningAction SilentlyContinue
                if ($testResult) {
                    $hasLogShipping = $true
                }
            } catch {
                # Log shipping not configured or not available
            }
        }

        It "Returns PSCustomObject" -Skip:(-not $hasLogShipping) {
            $testResult.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" -Skip:(-not $hasLogShipping) {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'InstanceType',
                'TimeSinceLastBackup',
                'LastBackupFile',
                'BackupThreshold',
                'IsBackupAlertEnabled',
                'TimeSinceLastCopy',
                'LastCopiedFile',
                'TimeSinceLastRestore',
                'LastRestoredFile',
                'LastRestoredLatency',
                'RestoreThreshold',
                'IsRestoreAlertEnabled',
                'Status'
            )
            $actualProps = $testResult[0].PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        Context "Output with -Simple" {
            BeforeAll {
                $simpleResult = $null
                if ($hasLogShipping) {
                    $simpleResult = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.instance2 -Simple -EnableException -WarningAction SilentlyContinue
                }
            }

            It "Returns only four essential properties when -Simple specified" -Skip:(-not $hasLogShipping) {
                $expectedProps = @(
                    'SqlInstance',
                    'Database',
                    'InstanceType',
                    'Status'
                )
                $actualProps = $simpleResult[0].PSObject.Properties.Name
                foreach ($prop in $expectedProps) {
                    $actualProps | Should -Contain $prop -Because "property '$prop' should be in -Simple output"
                }
            }
        }

        Context "Output with -Primary" {
            BeforeAll {
                $primaryResult = $null
                if ($hasLogShipping) {
                    $primaryResult = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.instance2 -Primary -EnableException -WarningAction SilentlyContinue
                }
            }

            It "Returns only primary instances when -Primary specified" -Skip:(-not $hasLogShipping) {
                if ($primaryResult) {
                    $primaryResult.InstanceType | Should -Be "Primary Instance"
                }
            }
        }

        Context "Output with -Secondary" {
            BeforeAll {
                $secondaryResult = $null
                if ($hasLogShipping) {
                    $secondaryResult = Test-DbaDbLogShipStatus -SqlInstance $TestConfig.instance2 -Secondary -EnableException -WarningAction SilentlyContinue
                }
            }

            It "Returns only secondary instances when -Secondary specified" -Skip:(-not $hasLogShipping) {
                if ($secondaryResult) {
                    $secondaryResult.InstanceType | Should -Be "Secondary Instance"
                }
            }
        }
    }
}