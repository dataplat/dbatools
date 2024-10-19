param($ModuleName = 'dbatools')

Describe "Expand-DbaDbLogFile" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $db1Name = "dbatoolsci_expand"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Expand-DbaDbLogFile
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have TargetLogSize parameter" {
            $CommandUnderTest | Should -HaveParameter TargetLogSize
        }
        It "Should have IncrementSize parameter" {
            $CommandUnderTest | Should -HaveParameter IncrementSize
        }
        It "Should have LogFileId parameter" {
            $CommandUnderTest | Should -HaveParameter LogFileId
        }
        It "Should have ShrinkLogFile parameter" {
            $CommandUnderTest | Should -HaveParameter ShrinkLogFile
        }
        It "Should have ShrinkSize parameter" {
            $CommandUnderTest | Should -HaveParameter ShrinkSize
        }
        It "Should have BackupDirectory parameter" {
            $CommandUnderTest | Should -HaveParameter BackupDirectory
        }
        It "Should have ExcludeDiskSpaceValidation parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDiskSpaceValidation
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Ensure command functionality" {
        BeforeAll {
            $db1 = New-DbaDatabase -SqlInstance $global:instance1 -Name $db1Name
            $results = Expand-DbaDbLogFile -SqlInstance $global:instance1 -Database $db1 -TargetLogSize 128
        }

        AfterAll {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database $db1Name
        }

        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'ID', 'Name', 'LogFileCount', 'InitialSize', 'CurrentSize', 'InitialVLFCount', 'CurrentVLFCount'
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Should have database name of $db1Name" {
            $results.Database | Should -Be $db1Name
        }

        It "Should have database ID of $($db1.ID)" {
            $results.DatabaseID | Should -Be $db1.ID
        }

        It "Should have grown the log file" {
            $results | ForEach-Object {
                $_.CurrentSize | Should -BeGreaterThan $_.InitialSize
            }
        }
    }
}
