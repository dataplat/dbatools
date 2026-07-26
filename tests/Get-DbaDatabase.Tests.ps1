#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDatabase",
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
                "Pattern",
                "ExcludeUser",
                "ExcludeSystem",
                "Owner",
                "Encrypted",
                "Status",
                "Access",
                "RecoveryModel",
                "NoFullBackup",
                "NoFullBackupSince",
                "NoLogBackup",
                "NoLogBackupSince",
                "IncludeLastUsed",
                "OnlyAccessible",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Mutually exclusive database filters" {
        It "warns without throwing or emitting data when both filters are bound" {
            $guardWarnings = @()
            $guardOutput = Get-DbaDatabase -SqlInstance "invalid" -ExcludeSystem -ExcludeUser -WarningAction SilentlyContinue -WarningVariable guardWarnings

            $guardOutput | Should -BeNullOrEmpty
            $guardWarnings.Count | Should -Be 1
            $guardWarnings[0].Message | Should -Match "\[Get-DbaDatabase\]"
            $guardWarnings[0].Message | Should -Match "You cannot specify both ExcludeUser and ExcludeSystem\."
        }

        It "preserves the nested warning exception identity for bound Stop" {
            $guardWarnings = @()
            $guardException = $null
            try {
                Get-DbaDatabase -SqlInstance "invalid" -ExcludeSystem -ExcludeUser -WarningAction Stop -WarningVariable guardWarnings
            } catch {
                $guardException = $PSItem
            }

            $guardException.Exception.GetType().FullName | Should -Be "System.Management.Automation.ActionPreferenceStopException"
            $guardException.FullyQualifiedErrorId | Should -Be "ActionPreferenceStop,Dataplat.Dbatools.Commands.WriteMessageCommand"
            $guardWarnings.Count | Should -Be 1
        }

        It "preserves the nested warning exception identity for ambient Stop" {
            $guardWarnings = @()
            $guardException = $null
            $previousWarningPreference = $global:WarningPreference
            try {
                $global:WarningPreference = "Stop"
                try {
                    Get-DbaDatabase -SqlInstance "invalid" -ExcludeSystem -ExcludeUser -WarningVariable guardWarnings
                } catch {
                    $guardException = $PSItem
                }
            } finally {
                $global:WarningPreference = $previousWarningPreference
            }

            $guardException.Exception.GetType().FullName | Should -Be "System.Management.Automation.ActionPreferenceStopException"
            $guardException.FullyQualifiedErrorId | Should -Be "ActionPreferenceStop,Dataplat.Dbatools.Commands.WriteMessageCommand"
            $guardWarnings.Count | Should -Be 1
        }

        It "appends one warning to a pre-populated WarningVariable" {
            $existingWarning = New-Object -TypeName System.Management.Automation.WarningRecord -ArgumentList "existing"
            $guardWarnings = [System.Collections.ArrayList]@($existingWarning)
            $guardOutput = Get-DbaDatabase -SqlInstance "invalid" -ExcludeSystem -ExcludeUser -WarningAction SilentlyContinue -WarningVariable +guardWarnings

            $guardOutput | Should -BeNullOrEmpty
            $guardWarnings.Count | Should -Be 2
            $guardWarnings[0].Message | Should -Be "existing"
            $guardWarnings[1].Message | Should -Match "You cannot specify both ExcludeUser and ExcludeSystem\."
        }

        It "throws the guard exception without warning records for EnableException" {
            $guardWarnings = @()
            $guardException = { Get-DbaDatabase -SqlInstance "invalid" -ExcludeSystem -ExcludeUser -EnableException -WarningVariable guardWarnings } |
                Should -Throw -PassThru

            $guardException.Exception.Message | Should -Be "You cannot specify both ExcludeUser and ExcludeSystem."
            $guardWarnings | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    Context "Count system databases on localhost" {
        It "reports the right number of databases" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -ExcludeUser
            $results.Count | Should -Be 4
        }
    }

    Context "Check that tempdb database is in Simple recovery mode" {
        It "tempdb's recovery mode is Simple" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database tempdb
            $results.RecoveryModel | Should -Be "Simple"
        }
    }

    Context "Check that master database is accessible" {
        It "master is accessible" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database master
            $results.IsAccessible | Should -BeTrue
        }
    }

}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $random = Get-Random
        $dbname1 = "dbatoolsci_Backup_$random"
        $dbname2 = "dbatoolsci_NoBackup_$random"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname1 , $dbname2
        $null = Backup-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Type Full -FilePath nul -Database $dbname1
    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname1, $dbname2 | Remove-DbaDatabase
    }

    Context "Results return if no backup" {
        It "Should not report as database has full backup" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname1 -NoFullBackup
            ($results).Count | Should -Be 0
        }
        It "Should report 1 database with no full backup" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname2 -NoFullBackup
            ($results).Count | Should -Be 1
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $random = Get-Random
        $dbPrefix = "dbatoolsci_pattern"
        $dbname1 = "${dbPrefix}_test1_$random"
        $dbname2 = "${dbPrefix}_test2_$random"
        $dbname3 = "${dbPrefix}_prod1_$random"
        $dbname4 = "other_database_$random"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $dbname1, $dbname2, $dbname3, $dbname4
    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname1, $dbname2, $dbname3, $dbname4 | Remove-DbaDatabase
    }

    Context "Pattern parameter filtering" {
        It "Should return databases matching pattern with regex" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Pattern "^${dbPrefix}_"
            $results.Name | Should -Contain $dbname1
            $results.Name | Should -Contain $dbname2
            $results.Name | Should -Contain $dbname3
            $results.Name | Should -Not -Contain $dbname4
        }

        It "Should return databases matching pattern with _test segment" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Pattern "^${dbPrefix}_test"
            $results.Name | Should -Contain $dbname1
            $results.Name | Should -Contain $dbname2
            $results.Name | Should -Not -Contain $dbname3
            $results.Name | Should -Not -Contain $dbname4
        }

        It "Should return databases matching multiple patterns" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Pattern "^${dbPrefix}_test", "^${dbPrefix}_prod"
            $results.Name | Should -Contain $dbname1
            $results.Name | Should -Contain $dbname2
            $results.Name | Should -Contain $dbname3
            $results.Name | Should -Not -Contain $dbname4
        }

        It "Should return no results for non-matching pattern" {
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Pattern "^nonexistent_"
            $results | Should -BeNullOrEmpty
        }
    }
}
