#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDatabase",
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
                "Name",
                "Collation",
                "Recoverymodel",
                "Owner",
                "DataFilePath",
                "LogFilePath",
                "PrimaryFilesize",
                "PrimaryFileGrowth",
                "PrimaryFileMaxSize",
                "LogSize",
                "LogGrowth",
                "LogMaxSize",
                "SecondaryFilesize",
                "SecondaryFileGrowth",
                "SecondaryFileMaxSize",
                "SecondaryFileCount",
                "DefaultFileGroup",
                "EnableException",
                "SecondaryDataFileSuffix",
                "LogFileSuffix",
                "DataFileSuffix"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When creating databases" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $random = Get-Random
            $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
            $instance3 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2

            $randomDb = New-DbaDatabase -SqlInstance $InstanceSingle

            $newDbName = "dbatoolsci_newdb_$random"
            $newDb1Name = "dbatoolsci_newdb1_$random"
            $newDb2Name = "dbatoolsci_newdb2_$random"
            $bug6780DbName = "dbatoolsci_6780_$random"
            $collationDbName = "dbatoolsci_collation_$random"
            $secondaryFileTestDbName = "dbatoolsci_secondaryfiletest_$random"
            $secondaryFileCountTestDbName = "dbatoolsci_secondaryfilecounttest_$random"
            $simpleRecoveryModelDbName = "dbatoolsci_simple_$random"
            $fullRecoveryModelDbName = "dbatoolsci_full_$random"
            $bulkLoggedRecoveryModelDbName = "dbatoolsci_bulklogged_$random"
            $primaryFileGroupDbName = "dbatoolsci_primary_filegroup_$random"
            $secondaryFileGroupDbName = "dbatoolsci_secondary_filegroup_$random"

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup all created databases.
            Get-DbaDatabase -SqlInstance $InstanceSingle, $instance3 -ExcludeSystem | Remove-DbaDatabase

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "creates one new randomly named database" {
            $randomDb.Name | Should -Match random
        }

        It "creates one new database on two servers" {
            $newDbOnTwoServers = New-DbaDatabase -SqlInstance $InstanceSingle, $instance3 -Name $newDbName -LogSize 32 -LogMaxSize 512 -PrimaryFilesize 64 -PrimaryFileMaxSize 512 -SecondaryFilesize 64 -SecondaryFileMaxSize 512 -LogGrowth 32 -PrimaryFileGrowth 64 -SecondaryFileGrowth 64 -DataFileSuffix "_PRIMARY" -LogFileSuffix "_Log" -SecondaryDataFileSuffix "_MainData"
            $newDbOnTwoServers.Count | Should -Be 2
            $newDbOnTwoServers[0].Name | Should -Be $newDbName
            $newDbOnTwoServers[1].Name | Should -Be $newDbName

            $InstanceSingle.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].Size | Should -Be 65536
            $InstanceSingle.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].MaxSize | Should -Be 524288
            $InstanceSingle.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].Growth | Should -Be 65536
            $InstanceSingle.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].GrowthType | Should -Be "KB"

            $InstanceSingle.Databases[$newDbName].LogFiles["$($newDbName)_log"].Size | Should -Be 32768
            $InstanceSingle.Databases[$newDbName].LogFiles["$($newDbName)_log"].MaxSize | Should -Be 524288
            $InstanceSingle.Databases[$newDbName].LogFiles["$($newDbName)_log"].Growth | Should -Be 32768
            $InstanceSingle.Databases[$newDbName].LogFiles["$($newDbName)_log"].GrowthType | Should -Be "KB"

            $InstanceSingle.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].Size | Should -Be 65536
            $InstanceSingle.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].MaxSize | Should -Be 524288
            $InstanceSingle.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].Growth | Should -Be 65536
            $InstanceSingle.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].GrowthType | Should -Be "KB"

            $instance3.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].Size | Should -Be 65536
            $instance3.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].MaxSize | Should -Be 524288
            $instance3.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].Growth | Should -Be 65536
            $instance3.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].GrowthType | Should -Be "KB"

            $instance3.Databases[$newDbName].LogFiles["$($newDbName)_log"].Size | Should -Be 32768
            $instance3.Databases[$newDbName].LogFiles["$($newDbName)_log"].MaxSize | Should -Be 524288
            $instance3.Databases[$newDbName].LogFiles["$($newDbName)_log"].Growth | Should -Be 32768
            $instance3.Databases[$newDbName].LogFiles["$($newDbName)_log"].GrowthType | Should -Be "KB"

            $instance3.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].Size | Should -Be 65536
            $instance3.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].MaxSize | Should -Be 524288
            $instance3.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].Growth | Should -Be 65536
            $instance3.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].GrowthType | Should -Be "KB"
        }

        It "creates two new databases on two servers" {
            $multipleDbOnTwoServers = New-DbaDatabase -SqlInstance $InstanceSingle, $instance3 -Name $newDb1Name, $newDb2Name
            $multipleDbOnTwoServers.Count | Should -Be 4
            $multipleDbOnTwoServers[0].Name | Should -Be $newDb1Name
            $multipleDbOnTwoServers[1].Name | Should -Be $newDb2Name
        }

        It "bug 6780 autogrowth params" {
            $db6780 = New-DbaDatabase -SqlInstance $InstanceSingle -Name $bug6780DbName -Recoverymodel Simple -DataFilePath $randomDb.PrimaryFilePath -LogFilePath $randomDb.PrimaryFilePath -SecondaryFileCount 1 -DataFileSuffix "_PRIMARY" -LogFileSuffix "_Log" -SecondaryDataFileSuffix "_MainData"
            $db6780.Count | Should -Be 1

            $InstanceSingle.Databases[$bug6780DbName].FileGroups["PRIMARY"].Files["$($bug6780DbName)_PRIMARY"].Growth | Should -Be $InstanceSingle.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Growth
            $InstanceSingle.Databases[$bug6780DbName].FileGroups["PRIMARY"].Files["$($bug6780DbName)_PRIMARY"].GrowthType | Should -Be $InstanceSingle.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].GrowthType

            $InstanceSingle.Databases[$bug6780DbName].LogFiles["$($bug6780DbName)_log"].Growth | Should -Be $InstanceSingle.Databases["model"].LogFiles["modellog"].Growth
            $InstanceSingle.Databases[$bug6780DbName].LogFiles["$($bug6780DbName)_log"].GrowthType | Should -Be $InstanceSingle.Databases["model"].LogFiles["modellog"].GrowthType

            # also check the randomDb since it was created without any additional params
            $InstanceSingle.Databases[$($randomDb.Name)].FileGroups["PRIMARY"].Files["$($randomDb.Name)"].Growth | Should -Be $InstanceSingle.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Growth
            $InstanceSingle.Databases[$($randomDb.Name)].FileGroups["PRIMARY"].Files["$($randomDb.Name)"].GrowthType | Should -Be $InstanceSingle.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].GrowthType

            $InstanceSingle.Databases[$($randomDb.Name)].LogFiles["$($randomDb.Name)_log"].Growth | Should -Be $InstanceSingle.Databases["model"].LogFiles["modellog"].Growth
            $InstanceSingle.Databases[$($randomDb.Name)].LogFiles["$($randomDb.Name)_log"].GrowthType | Should -Be $InstanceSingle.Databases["model"].LogFiles["modellog"].GrowthType
        }

        It "collation is validated" {
            $collationDb = New-DbaDatabase -SqlInstance $InstanceSingle -Name $collationDbName -Collation "invalid_collation" -WarningAction SilentlyContinue
            $collationDb | Should -BeNull

            $collationDb = New-DbaDatabase -SqlInstance $InstanceSingle -Name $collationDbName -Collation $InstanceSingle.Databases["model"].Collation
            $InstanceSingle.Databases[$collationDbName].Collation | Should -Be $InstanceSingle.Databases["model"].Collation
        }

        It "SecondaryFilesize is specified but not the SecondaryFileCount" {
            $secondaryFileTestDb = New-DbaDatabase -SqlInstance $instance3 -Name $secondaryFileTestDbName -SecondaryFilesize 10 -DataFileSuffix "_PRIMARY" -LogFileSuffix "_Log" -SecondaryDataFileSuffix "_MainData"
            $instance3.Databases[$secondaryFileTestDbName].FileGroups["$($secondaryFileTestDbName)_MainData"].Files.Count | Should -Be 1
            $instance3.Databases[$secondaryFileTestDbName].FileGroups["$($secondaryFileTestDbName)_MainData"].Files[0].Size | Should -Be 10240
        }

        It "SecondaryFileCount is specified but not the other secondary file params" {
            $secondaryFileCountTestDb = New-DbaDatabase -SqlInstance $instance3 -Name $secondaryFileCountTestDbName -SecondaryFileCount 2 -DataFileSuffix "_PRIMARY" -LogFileSuffix "_Log" -SecondaryDataFileSuffix "_MainData"
            $instance3.Databases[$secondaryFileCountTestDbName].FileGroups["$($secondaryFileCountTestDbName)_MainData"].Files.Count | Should -Be 2
            $instance3.Databases[$secondaryFileCountTestDbName].FileGroups["$($secondaryFileCountTestDbName)_MainData"].Files[0].Size | Should -Be $instance3.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size
            $instance3.Databases[$secondaryFileCountTestDbName].FileGroups["$($secondaryFileCountTestDbName)_MainData"].Files[1].Size | Should -Be $instance3.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Size
        }

        It "RecoveryModel" {
            $simpleRecoveryModelDb = New-DbaDatabase -SqlInstance $InstanceSingle -Name $simpleRecoveryModelDbName -RecoveryModel Simple
            $simpleRecoveryModelDb.RecoveryModel | Should -Be "Simple"

            $fullRecoveryModelDb = New-DbaDatabase -SqlInstance $InstanceSingle -Name $fullRecoveryModelDbName -RecoveryModel Full
            $fullRecoveryModelDb.RecoveryModel | Should -Be "Full"

            $bulkLoggedRecoveryModelDb = New-DbaDatabase -SqlInstance $InstanceSingle -Name $bulkLoggedRecoveryModelDbName -RecoveryModel BulkLogged
            $bulkLoggedRecoveryModelDb.RecoveryModel | Should -Be "BulkLogged"
        }

        It "DefaultFileGroup" {
            $primaryFileGroupDb = New-DbaDatabase -SqlInstance $instance3 -Name $primaryFileGroupDbName -DefaultFileGroup "Primary"
            $primaryFileGroupDb.DefaultFileGroup | Should -Be "PRIMARY"

            $secondaryFileGroupDb = New-DbaDatabase -SqlInstance $instance3 -Name $secondaryFileGroupDbName -DefaultFileGroup "Secondary" -DataFileSuffix "_PRIMARY" -LogFileSuffix "_Log" -SecondaryDataFileSuffix "_MainData"
            $secondaryFileGroupDb.DefaultFileGroup | Should -Be "$($secondaryFileGroupDbName)_MainData"
        }
    }

    Context "Output validation" {
        BeforeAll {
            $outputTestDbName = "dbatoolsci_outputtest_$(Get-Random)"
            $result = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $outputTestDbName
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $outputTestDbName -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result.psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Database"
        }

        It "Has the expected default display properties" {
            $result | Should -Not -BeNullOrEmpty
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Name", "Status", "IsAccessible", "RecoveryModel", "LogReuseWaitStatus", "SizeMB", "Compatibility", "Collation", "Owner", "Encrypted", "LastFullBackup", "LastDiffBackup", "LastLogBackup")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias properties" {
            $result | Should -Not -BeNullOrEmpty
            $result.psobject.Properties["SizeMB"] | Should -Not -BeNullOrEmpty
            $result.psobject.Properties["SizeMB"].MemberType | Should -Be "AliasProperty"
        }
    }
}