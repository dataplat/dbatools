#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "ConvertTo-DbaTimeline",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "InputObject",
                "ExcludeRowLabel",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    Context "Growth event input" {
        BeforeAll {
            $growthEvent = [PSCustomObject]@{
                SqlInstance  = "sql1"
                InstanceName = "MSSQLSERVER"
                EventClass   = 92
                ChangeInSize = 16
                DatabaseName = "MyDb"
                StartTime    = [datetime]"2024-01-01T00:00:00"
                EndTime      = [datetime]"2024-01-01T00:01:00"
            }
            $growthEventWithQuote = [PSCustomObject]@{
                SqlInstance  = "sql1"
                InstanceName = "MSSQLSERVER"
                EventClass   = 92
                ChangeInSize = 16
                DatabaseName = "O'Reilly"
                StartTime    = [datetime]"2024-01-01T00:00:00"
                EndTime      = [datetime]"2024-01-01T00:01:00"
            }
        }

        It "Supports Find-DbaDbGrowthEvent style input" {
            $result = $growthEvent | ConvertTo-DbaTimeline

            $result | Should -HaveCount 3
            $result[1] | Should -Match "Data Grow"
            $result[2] | Should -Match ([regex]::Escape("<code>Find-DbaDbGrowthEvent</code>"))
        }

        It "Escapes database names for JavaScript output" {
            $result = $growthEventWithQuote | ConvertTo-DbaTimeline

            $result[1] | Should -BeLike "*O\'Reilly*"
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidance.
#>

Describe "$CommandName compiled-cmdlet characterization" -Tag IntegrationTests {
    BeforeAll {
        # Characterization scenarios for the migration gate (which executes -Tag IntegrationTests):
        # ConvertTo-DbaTimeline is pure compute (HTML/JS text generation), so these run everywhere
        # with no SQL instance. Expected values were captured against the current script function on
        # both editions (PS 5.1 and PS 7); the JS row literals are pinned as single-quoted
        # here-strings because the exact quoting is the contract.
        function New-CharJobHistory {
            param([string]$Instance, [string]$Job, [string]$Status, [datetime]$Start, [datetime]$End)
            $fake = New-Object -TypeName psobject
            Add-Member -InputObject $fake -MemberType NoteProperty -Name SqlInstance -Value $Instance
            Add-Member -InputObject $fake -MemberType NoteProperty -Name InstanceName -Value "MSSQLSERVER"
            Add-Member -InputObject $fake -MemberType NoteProperty -Name TypeName -Value "AgentJobHistory"
            Add-Member -InputObject $fake -MemberType NoteProperty -Name Job -Value $Job
            Add-Member -InputObject $fake -MemberType NoteProperty -Name Status -Value $Status
            Add-Member -InputObject $fake -MemberType NoteProperty -Name StartDate -Value $Start
            Add-Member -InputObject $fake -MemberType NoteProperty -Name EndDate -Value $End
            $fake
        }
        function New-CharGrowthEvent {
            param([string]$Instance, [string]$Db, [int]$EventClass, [datetime]$Start, [datetime]$End)
            $fake = New-Object -TypeName psobject
            Add-Member -InputObject $fake -MemberType NoteProperty -Name SqlInstance -Value $Instance
            Add-Member -InputObject $fake -MemberType NoteProperty -Name DatabaseName -Value $Db
            Add-Member -InputObject $fake -MemberType NoteProperty -Name EventClass -Value $EventClass
            Add-Member -InputObject $fake -MemberType NoteProperty -Name ChangeInSize -Value 1024
            Add-Member -InputObject $fake -MemberType NoteProperty -Name StartTime -Value $Start
            Add-Member -InputObject $fake -MemberType NoteProperty -Name EndTime -Value $End
            $fake
        }

        $charJobOne = New-CharJobHistory -Instance "sql01" -Job "Backup Job" -Status "Succeeded" -Start ([datetime]"2026-01-02 03:04:05") -End ([datetime]"2026-01-02 03:14:05")
        $charJobTwo = New-CharJobHistory -Instance "sql01" -Job "Index Job" -Status "Failed" -Start ([datetime]"2026-01-02 04:00:00") -End ([datetime]"2026-01-02 04:30:00")

        $charBackup = New-Object -TypeName Dataplat.Dbatools.Database.BackupHistory
        $charBackup.SqlInstance = "sql01"
        $charBackup.InstanceName = "MSSQLSERVER"
        $charBackup.Database = "master"
        $charBackup.Type = "Full"
        $charBackup.Start = [Dataplat.Dbatools.Utility.DbaDateTime]([datetime]"2026-01-02 01:00:00")
        $charBackup.End = [Dataplat.Dbatools.Utility.DbaDateTime]([datetime]"2026-01-02 01:05:00")

        $charJunk = New-Object -TypeName psobject
        Add-Member -InputObject $charJunk -MemberType NoteProperty -Name Whatever -Value 1

        # The exact body rows the current function renders (single-instance label strip applied;
        # month is the JS 0-based "MM"-1 int while day/hour/minute/second keep leading zeros).
        $expectedJobRowOne = @'
['Backup Job','Succeeded','#36B300',new Date(2026, 0, 02, 03, 04, 05), new Date(2026, 0, 02, 03, 14, 05)],
'@
        $expectedJobRowTwo = @'
['Index Job','Failed','#FF3D3D',new Date(2026, 0, 02, 04, 00, 00), new Date(2026, 0, 02, 04, 30, 00)],
'@
        $expectedBackupRow = @'
['master','Full','',new Date(2026, 0, 02, 01, 00, 00), new Date(2026, 0, 02, 01, 05, 00)],
'@
        $expectedGrowthGrow = @'
'Data Grow','#36B300'
'@
        $expectedGrowthShrink = @'
'Log Shrink','#FF8C00'
'@
        $expectedGrowthUnknown = @'
'Unknown','#FF8C00'
'@
    }

    Context "Output shape" {
        It "Emits header string, body row collection, and footer string for direct input" {
            $result = ConvertTo-DbaTimeline -InputObject @($charJobOne, $charJobTwo)
            @($result).Count | Should -Be 3
            $result[0] | Should -Match "<html>"
            $result[1].Count | Should -Be 1
            $result[2] | Should -Match "</html>"
        }

        It "Keeps one body string per pipeline process block" {
            $result = @($charJobOne, $charJobTwo) | ConvertTo-DbaTimeline
            @($result).Count | Should -Be 3
            $result[1].Count | Should -Be 2
        }
    }

    Context "Agent job history rendering" {
        It "Renders JS rows with status colors, 0-based month, and zero-padded parts" {
            $result = ConvertTo-DbaTimeline -InputObject @($charJobOne, $charJobTwo)
            $bodyText = "$($result[1])"
            $bodyText | Should -Match ([regex]::Escape($expectedJobRowOne.Trim()))
            $bodyText | Should -Match ([regex]::Escape($expectedJobRowTwo.Trim()))
        }

        It "Strips the instance row label when only one server is present" {
            $result = ConvertTo-DbaTimeline -InputObject @($charJobOne, $charJobTwo)
            "$($result[1])" | Should -Not -Match ([regex]::Escape("[sql01]"))
        }

        It "Names the caller and server in the footer and shows row labels by default" {
            $result = ConvertTo-DbaTimeline -InputObject @($charJobOne, $charJobTwo)
            $result[2] | Should -Match ([regex]::Escape("<code>Get-DbaAgentJobHistory</code>"))
            $result[2] | Should -Match ([regex]::Escape("<code>sql01</code>"))
            $result[2] | Should -Match ([regex]::Escape("showRowLabels: true"))
        }

        It "Flips showRowLabels to false with ExcludeRowLabel" {
            $result = ConvertTo-DbaTimeline -InputObject @($charJobOne, $charJobTwo) -ExcludeRowLabel
            $result[2] | Should -Match ([regex]::Escape("showRowLabels: false"))
        }
    }

    Context "Growth event rendering" {
        It "Maps EventClass 92/95 and unknown classes to labels and colors" {
            $growthRows = @(
                (New-CharGrowthEvent -Instance "sql01" -Db "db1" -EventClass 92 -Start ([datetime]"2026-01-02 03:00:00") -End ([datetime]"2026-01-02 03:00:05")),
                (New-CharGrowthEvent -Instance "sql01" -Db "db1" -EventClass 95 -Start ([datetime]"2026-01-02 03:01:00") -End ([datetime]"2026-01-02 03:01:05")),
                (New-CharGrowthEvent -Instance "sql01" -Db "db1" -EventClass 42 -Start ([datetime]"2026-01-02 03:02:00") -End ([datetime]"2026-01-02 03:02:05"))
            )
            $result = ConvertTo-DbaTimeline -InputObject $growthRows
            $bodyText = "$($result[1])"
            $bodyText | Should -Match ([regex]::Escape($expectedGrowthGrow.Trim()))
            $bodyText | Should -Match ([regex]::Escape($expectedGrowthShrink.Trim()))
            $bodyText | Should -Match ([regex]::Escape($expectedGrowthUnknown.Trim()))
            $result[2] | Should -Match ([regex]::Escape("<code>Find-DbaDbGrowthEvent</code>"))
        }
    }

    Context "Backup history rendering" {
        It "Detects the BackupHistory type and renders an empty style field" {
            $result = ConvertTo-DbaTimeline -InputObject @($charBackup)
            "$($result[1])" | Should -Match ([regex]::Escape($expectedBackupRow.Trim()))
            # The source assigns this caller name with a LEADING SPACE - characterized as-is.
            $result[2] | Should -Match ([regex]::Escape("<code> Get-DbaDbBackupHistory</code>"))
        }
    }

    Context "Unsupported input" {
        It "Warns and emits nothing for unsupported input" {
            $result = ConvertTo-DbaTimeline -InputObject $charJunk -WarningVariable charWarn -WarningAction SilentlyContinue
            @($result).Count | Should -Be 0
            $charWarn | Should -Match "Unsupported input data"
        }

        It "Throws for unsupported input when EnableException is set" {
            { ConvertTo-DbaTimeline -InputObject $charJunk -EnableException -WarningAction SilentlyContinue } | Should -Throw "*Unsupported input data*"
        }
    }
}
