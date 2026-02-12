#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaBackupDevice",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "BackupDevice",
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

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test copying backup devices, we need to create a backup device on the source instance
        # and test copying it to the destination instance.

        # Set variables. They are available in all the It blocks.
        $deviceName = "dbatoolsci-backupdevice-$(Get-Random)"
        $backupFileName = "$backupPath\$deviceName.bak"
        $sourceServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1
        $destServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2

        # Create the objects.
        $sourceServer.Query("EXEC master.dbo.sp_addumpdevice @devtype = N'disk', @logicalname = N'$deviceName', @physicalname = N'$backupFileName'")
        $sourceServer.Query("BACKUP DATABASE master TO DISK = '$backupFileName'")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $sourceServer.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$deviceName'")
        try {
            $destServer.Query("EXEC master.dbo.sp_dropdevice @logicalname = N'$deviceName'")
        } catch {
            # Device may not exist, ignore error
        }

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying backup device between instances" {
        It "Should copy the backup device successfully or warn about local copy" {
            $results = Copy-DbaBackupDevice -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -WarningVariable WarnVar -WarningAction SilentlyContinue 3> $null

            if ($WarnVar) {
                $WarnVar | Should -Match "backup device to destination"
            } else {
                $results.Status | Should -Be "Successful"
            }
        }

        It "Should skip copying when device already exists" {
            $results = Copy-DbaBackupDevice -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2
            $results.Status | Should -Not -Be "Successful"
        }

        It "Returns output with the expected TypeName" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $results[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}