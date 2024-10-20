param($ModuleName = 'dbatools')

Describe "Get-DbaAgBackupHistory" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaAgBackupHistory
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "AvailabilityGroup",
            "Database",
            "ExcludeDatabase",
            "IncludeCopyOnly",
            "Force",
            "Since",
            "RecoveryFork",
            "Last",
            "LastFull",
            "LastDiff",
            "LastLog",
            "DeviceType",
            "Raw",
            "LastLsn",
            "IncludeMirror",
            "Type",
            "LsnSort",
            "EnableException"
        )

        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }
}

# No Integration Tests, because we don't have an availability group running in AppVeyor
