param($ModuleName = 'dbatools')

Describe "Test-DbaBackupInformation Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaBackupInformation
        }
        It "Should have BackupHistory as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupHistory
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have WithReplace as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter WithReplace
        }
        It "Should have Continue as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Continue
        }
        It "Should have VerifyOnly as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter VerifyOnly
        }
        It "Should have OutputScriptOnly as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter OutputScriptOnly
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Test-DbaBackupInformation Integration Tests" -Tag 'IntegrationTests' {
    BeforeAll {
        $BackupHistory = Import-CliXml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
        $BackupHistory = $BackupHistory | Format-DbaBackupInformation

        Mock Connect-DbaInstance -MockWith {
            $obj = [PSCustomObject]@{
                Name                 = 'BASEName'
                NetName              = 'BASENetName'
                ComputerName         = 'BASEComputerName'
                InstanceName         = 'BASEInstanceName'
                DomainInstanceName   = 'BASEDomainInstanceName'
                InstallDataDirectory = 'BASEInstallDataDirectory'
                ErrorLogPath         = 'BASEErrorLog_{0}_{1}_{2}_Path' -f "'", '"', ']'
                ServiceName          = 'BASEServiceName'
                VersionMajor         = 9
                ConnectionContext    = New-Object PSObject
            }
            Add-Member -InputObject $obj.ConnectionContext -Name ConnectionString  -MemberType NoteProperty -Value 'put=an=equal=in=it'
            Add-Member -InputObject $obj -Name Query -MemberType ScriptMethod -Value {
                param($query)
                if ($query -eq "SELECT DB_NAME(database_id) AS Name, physical_name AS PhysicalName FROM sys.master_files") {
                    return @(
                        @{ "Name"          = "master"
                            "PhysicalName" = "C:\temp\master.mdf"
                        }
                    )
                }
            }
            $obj.PSObject.TypeNames.Clear()
            $obj.PSObject.TypeNames.Add("Microsoft.SqlServer.Management.Smo.Server")
            return $obj
        } -ModuleName $ModuleName

        Mock Get-DbaDatabase { $null } -ModuleName $ModuleName
        Mock New-DbaDirectory {$true} -ModuleName $ModuleName
        Mock Test-DbaPath { 
            [pscustomobject]@{
                FilePath   = 'does\exists'
                FileExists = $true
            }
        } -ModuleName $ModuleName
    }

    Context "Everything as it should" {
        It "Should pass as all systems Green" {
            $output = $BackupHistory | Test-DbaBackupInformation -SqlInstance NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
            $output.Count | Should -BeGreaterThan 0
            $output.IsVerified | Should -Not -Contain $false
            $warnVar | Should -Not -BeNullOrEmpty
        }
    }

    Context "Not being able to see backups is bad" {
        BeforeAll {
            Mock Test-DbaPath { 
                [pscustomobject]@{
                    FilePath   = 'does\not\exists'
                    FileExists = $false
                }
            } -ModuleName $ModuleName
        }

        It "Should return fail as backup files don't exist" {
            $output = $BackupHistory | Test-DbaBackupInformation -SqlInstance NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
            $output.Count | Should -BeGreaterThan 0
            $output.IsVerified | Should -Not -Contain $true
            $warnVar | Should -Not -BeNullOrEmpty
        }
    }

    Context "Multiple source dbs for restore is bad" {
        BeforeAll {
            $BackupHistoryModified = $BackupHistory.Clone()
            $BackupHistoryModified[1].OriginalDatabase = 'Error'
        }

        It "Should return fail as 2 origin dbs" {
            $output = $BackupHistoryModified | Test-DbaBackupInformation -SqlInstance NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
            $output.Count | Should -BeGreaterThan 0
            $output.IsVerified | Should -Not -Contain $true
            $warnVar | Should -Not -BeNullOrEmpty
        }
    }

    Context "Fail if Destination db exists" {
        BeforeAll {
            Mock Get-DbaDatabase { '1' } -ModuleName $ModuleName
        }

        It "Should return fail if dest db exists" {
            $output = $BackupHistory | Test-DbaBackupInformation -SqlInstance NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
            $output.Count | Should -BeGreaterThan 0
            $output.IsVerified | Should -Not -Contain $true
            $warnVar | Should -Not -BeNullOrEmpty
        }
    }

    Context "Pass if Destination db exists and WithReplace set" {
        BeforeAll {
            Mock Get-DbaDatabase { '1' } -ModuleName $ModuleName
        }

        It "Should pass if destdb exists and WithReplace specified" {
            $output = $BackupHistory | Test-DbaBackupInformation -SqlInstance NotExist -WarningVariable warnvar -WarningAction SilentlyContinue -WithReplace
            $output.Count | Should -BeGreaterThan 0
            $output.IsVerified | Should -Not -Contain $true
            $warnVar | Should -Not -BeNullOrEmpty
        }
    }
}
