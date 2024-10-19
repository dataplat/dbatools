param($ModuleName = 'dbatools')

Describe "New-DbaDatabase" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $global:instance2
        $instance3 = Connect-DbaInstance -SqlInstance $global:instance3
        $null = Get-DbaProcess -SqlInstance $instance2, $instance3 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false
        $randomDb = New-DbaDatabase -SqlInstance $instance2
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
    }

    AfterAll {
        $null = Remove-DbaDatabase -SqlInstance $instance2 -Database $randomDb.Name, $newDbName, $newDb1Name, $newDb2Name, $bug6780DbName, $collationDbName, $simpleRecoveryModelDbName, $fullRecoveryModelDbName, $bulkLoggedRecoveryModelDbName -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $instance3 -Database $newDbName, $newDb1Name, $newDb2Name, $secondaryFileTestDbName, $secondaryFileCountTestDbName, $primaryFileGroupDbName, $secondaryFileGroupDbName -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDatabase
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Name parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have Collation parameter" {
            $CommandUnderTest | Should -HaveParameter Collation
        }
        It "Should have RecoveryModel parameter" {
            $CommandUnderTest | Should -HaveParameter RecoveryModel
        }
        It "Should have Owner parameter" {
            $CommandUnderTest | Should -HaveParameter Owner
        }
        It "Should have DataFilePath parameter" {
            $CommandUnderTest | Should -HaveParameter DataFilePath
        }
        It "Should have LogFilePath parameter" {
            $CommandUnderTest | Should -HaveParameter LogFilePath
        }
        It "Should have PrimaryFilesize parameter" {
            $CommandUnderTest | Should -HaveParameter PrimaryFilesize
        }
        It "Should have PrimaryFileGrowth parameter" {
            $CommandUnderTest | Should -HaveParameter PrimaryFileGrowth
        }
        It "Should have PrimaryFileMaxSize parameter" {
            $CommandUnderTest | Should -HaveParameter PrimaryFileMaxSize
        }
        It "Should have LogSize parameter" {
            $CommandUnderTest | Should -HaveParameter LogSize
        }
        It "Should have LogGrowth parameter" {
            $CommandUnderTest | Should -HaveParameter LogGrowth
        }
        It "Should have LogMaxSize parameter" {
            $CommandUnderTest | Should -HaveParameter LogMaxSize
        }
        It "Should have SecondaryFilesize parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryFilesize
        }
        It "Should have SecondaryFileGrowth parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryFileGrowth
        }
        It "Should have SecondaryFileMaxSize parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryFileMaxSize
        }
        It "Should have SecondaryFileCount parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryFileCount
        }
        It "Should have DefaultFileGroup parameter" {
            $CommandUnderTest | Should -HaveParameter DefaultFileGroup
        }
        It "Should have DataFileSuffix parameter" {
            $CommandUnderTest | Should -HaveParameter DataFileSuffix
        }
        It "Should have LogFileSuffix parameter" {
            $CommandUnderTest | Should -HaveParameter LogFileSuffix
        }
        It "Should have SecondaryDataFileSuffix parameter" {
            $CommandUnderTest | Should -HaveParameter SecondaryDataFileSuffix
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "commands work as expected" {
        It "creates one new randomly named database" {
            $randomDb.Name | Should -Match random
        }

        It "creates one new database on two servers" {
            $newDbOnTwoServers = New-DbaDatabase -SqlInstance $instance2, $instance3 -Name $newDbName -LogSize 32 -LogMaxSize 512 -PrimaryFilesize 64 -PrimaryFileMaxSize 512 -SecondaryFilesize 64 -SecondaryFileMaxSize 512 -LogGrowth 32 -PrimaryFileGrowth 64 -SecondaryFileGrowth 64 -DataFileSuffix "_PRIMARY" -LogFileSuffix "_Log" -SecondaryDataFileSuffix "_MainData"
            $newDbOnTwoServers.Count | Should -Be 2
            $newDbOnTwoServers[0].Name | Should -Be $newDbName
            $newDbOnTwoServers[1].Name | Should -Be $newDbName

            $instance2.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].Size | Should -Be 65536
            $instance2.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].MaxSize | Should -Be 524288
            $instance2.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].Growth | Should -Be 65536
            $instance2.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].GrowthType | Should -Be 'KB'

            $instance2.Databases[$newDbName].LogFiles["$($newDbName)_log"].Size | Should -Be 32768
            $instance2.Databases[$newDbName].LogFiles["$($newDbName)_log"].MaxSize | Should -Be 524288
            $instance2.Databases[$newDbName].LogFiles["$($newDbName)_log"].Growth | Should -Be 32768
            $instance2.Databases[$newDbName].LogFiles["$($newDbName)_log"].GrowthType | Should -Be 'KB'

            $instance2.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].Size | Should -Be 65536
            $instance2.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].MaxSize | Should -Be 524288
            $instance2.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].Growth | Should -Be 65536
            $instance2.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].GrowthType | Should -Be 'KB'

            $instance3.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].Size | Should -Be 65536
            $instance3.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].MaxSize | Should -Be 524288
            $instance3.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].Growth | Should -Be 65536
            $instance3.Databases[$newDbName].FileGroups["PRIMARY"].Files["$($newDbName)_PRIMARY"].GrowthType | Should -Be 'KB'

            $instance3.Databases[$newDbName].LogFiles["$($newDbName)_log"].Size | Should -Be 32768
            $instance3.Databases[$newDbName].LogFiles["$($newDbName)_log"].MaxSize | Should -Be 524288
            $instance3.Databases[$newDbName].LogFiles["$($newDbName)_log"].Growth | Should -Be 32768
            $instance3.Databases[$newDbName].LogFiles["$($newDbName)_log"].GrowthType | Should -Be 'KB'

            $instance3.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].Size | Should -Be 65536
            $instance3.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].MaxSize | Should -Be 524288
            $instance3.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].Growth | Should -Be 65536
            $instance3.Databases[$newDbName].FileGroups["$($newDbName)_MainData"].Files[0].GrowthType | Should -Be 'KB'
        }

        It "creates two new databases on two servers" {
            $multipleDbOnTwoServers = New-DbaDatabase -SqlInstance $instance2, $instance3 -Name $newDb1Name, $newDb2Name
            $multipleDbOnTwoServers.Count | Should -Be 4
            $multipleDbOnTwoServers[0].Name | Should -Be $newDb1Name
            $multipleDbOnTwoServers[1].Name | Should -Be $newDb2Name
        }

        It "bug 6780 autogrowth params" {
            $db6780 = New-DbaDatabase -SqlInstance $instance2 -Name $bug6780DbName -Recoverymodel Simple -DataFilePath $randomDb.PrimaryFilePath -LogFilePath $randomDb.PrimaryFilePath -SecondaryFileCount 1 -DataFileSuffix "_PRIMARY" -LogFileSuffix "_Log" -SecondaryDataFileSuffix "_MainData"
            $db6780.Count | Should -Be 1

            $instance2.Databases[$bug6780DbName].FileGroups["PRIMARY"].Files["$($bug6780DbName)_PRIMARY"].Growth | Should -Be $instance2.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Growth
            $instance2.Databases[$bug6780DbName].FileGroups["PRIMARY"].Files["$($bug6780DbName)_PRIMARY"].GrowthType | Should -Be $instance2.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].GrowthType

            $instance2.Databases[$bug6780DbName].LogFiles["$($bug6780DbName)_log"].Growth | Should -Be $instance2.Databases["model"].LogFiles["modellog"].Growth
            $instance2.Databases[$bug6780DbName].LogFiles["$($bug6780DbName)_log"].GrowthType | Should -Be $instance2.Databases["model"].LogFiles["modellog"].GrowthType

            # also check the randomDb since it was created without any additional params
            $instance2.Databases[$($randomDb.Name)].FileGroups["PRIMARY"].Files["$($randomDb.Name)"].Growth | Should -Be $instance2.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].Growth
            $instance2.Databases[$($randomDb.Name)].FileGroups["PRIMARY"].Files["$($randomDb.Name)"].GrowthType | Should -Be $instance2.Databases["model"].FileGroups["PRIMARY"].Files["modeldev"].GrowthType

            $instance2.Databases[$($randomDb.Name)].LogFiles["$($randomDb.Name)_log"].Growth | Should -Be $instance2.Databases["model"].LogFiles["modellog"].Growth
            $instance2.Databases[$($randomDb.Name)].LogFiles["$($randomDb.Name)_log"].GrowthType | Should -Be $instance2.Databases["model"].LogFiles["modellog"].GrowthType
        }

        It "collation is validated" {
            $collationDb = New-DbaDatabase -SqlInstance $instance2 -Name $collationDbName -Collation "invalid_collation"
            $collationDb | Should -BeNullOrEmpty

            $collationDb = New-DbaDatabase -SqlInstance $instance2 -Name $collationDbName -Collation $instance2.Databases["model"].Collation
            $instance2.Databases[$collationDbName].Collation | Should -Be $instance2.Databases["model"].Collation
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
            $simpleRecoveryModelDb = New-DbaDatabase -SqlInstance $instance2 -Name $simpleRecoveryModelDbName -RecoveryModel Simple
            $simpleRecoveryModelDb.RecoveryModel | Should -Be "Simple"

            $fullRecoveryModelDb = New-DbaDatabase -SqlInstance $instance2 -Name $fullRecoveryModelDbName -RecoveryModel Full
            $fullRecoveryModelDb.RecoveryModel | Should -Be "Full"

            $bulkLoggedRecoveryModelDb = New-DbaDatabase -SqlInstance $instance2 -Name $bulkLoggedRecoveryModelDbName -RecoveryModel BulkLogged
            $bulkLoggedRecoveryModelDb.RecoveryModel | Should -Be "BulkLogged"
        }

        It "DefaultFileGroup" {
            $primaryFileGroupDb = New-DbaDatabase -SqlInstance $instance3 -Name $primaryFileGroupDbName -DefaultFileGroup "Primary"
            $primaryFileGroupDb.DefaultFileGroup | Should -Be "PRIMARY"

            $secondaryFileGroupDb = New-DbaDatabase -SqlInstance $instance3 -Name $secondaryFileGroupDbName -DefaultFileGroup "Secondary" -DataFileSuffix "_PRIMARY" -LogFileSuffix "_Log" -SecondaryDataFileSuffix "_MainData"
            $secondaryFileGroupDb.DefaultFileGroup | Should -Be "$($secondaryFileGroupDbName)_MainData"
        }
    }
}
