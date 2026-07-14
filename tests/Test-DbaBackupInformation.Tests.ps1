#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Test-DbaBackupInformation",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "BackupHistory",
                "SqlInstance",
                "SqlCredential",
                "WithReplace",
                "Continue",
                "VerifyOnly",
                "OutputScriptOnly",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "Azure SQL Managed Instance file validation" {
            BeforeEach {
                $script:mockServer = [PSCustomObject]@{
                    Name                  = "sqlmi"
                    ComputerName          = "sqlmi"
                    VersionMajor          = 12
                    DatabaseEngineEdition = "SqlManagedInstance"
                    ServiceAccount        = ""
                }
                $script:mockServer.PSObject.TypeNames.Insert(0, "Microsoft.SqlServer.Management.Smo.Server")
                $script:backupHistory = [PSCustomObject]@{
                    Database         = "testdb"
                    OriginalDatabase = "testdb"
                    FileList         = @(
                        [PSCustomObject]@{
                            PhysicalName = "C:\data\orphan.xtp"
                        }
                    )
                    FullName         = "https://storage/backups/testdb.bak"
                }

                Mock Connect-DbaInstance { $script:mockServer }
                Mock Get-DbaDbPhysicalFile { @() }
                Mock Get-DbaDatabase { $null }
                Mock Get-DbaPathSep { "\" }
                Mock Test-DbaLsnChain { $true }
                Mock Test-DbaPath {
                    $Path | ForEach-Object {
                        [PSCustomObject]@{
                            FilePath   = $PSItem
                            FileExists = $true
                        }
                    }
                }
            }

            It "allows an orphaned XTP container because Managed Instance assigns a new path" {
                $output = $script:backupHistory | Test-DbaBackupInformation -SqlInstance "sqlmi" -WarningAction SilentlyContinue

                $output.IsVerified | Should -BeTrue
            }

            It "continues to reject other orphaned files on Managed Instance" {
                $script:backupHistory.FileList[0].PhysicalName = "C:\data\orphan.mdf"

                $output = $script:backupHistory | Test-DbaBackupInformation -SqlInstance "sqlmi" -WarningAction SilentlyContinue

                $output.IsVerified | Should -BeFalse
            }

            It "continues to reject orphaned XTP containers outside Managed Instance" {
                $script:mockServer.DatabaseEngineEdition = "Enterprise"

                $output = $script:backupHistory | Test-DbaBackupInformation -SqlInstance "sql1" -WarningAction SilentlyContinue

                $output.IsVerified | Should -BeFalse
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    InModuleScope dbatools {
        Context "Everything as it should" {
            It "Should pass as all systems Green" {
                $BackupHistory = Import-Clixml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
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
                }
                Mock Get-DbaDatabase { $null }

                Mock New-DbaDirectory { $true }
                Mock Test-DbaPath { [PSCustomObject]@{
                        FilePath   = 'does\exists'
                        FileExists = $true
                    }
                }
                Mock New-DbaDirectory { $True }
                $output = $BackupHistory | Test-DbaBackupInformation -SqlInstance NotExist -WarningAction SilentlyContinue
                $WarnVar | Should -BeNullOrEmpty
                $output | Should -Not -BeNullOrEmpty
                $output.IsVerified | Should -Not -Contain $false
            }
        }
        Context "Not being able to see backups is bad" {
            It "Should return fail as backup files don't exist" {
                $BackupHistory = Import-Clixml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
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
                }
                Mock Get-DbaDatabase { $null }
                Mock New-DbaDirectory { $true }
                Mock Test-DbaPath { [PSCustomObject]@{
                        FilePath   = 'does\not\exists'
                        FileExists = $false
                    }
                }
                Mock New-DbaDirectory { $True }
                $output = $BackupHistory | Test-DbaBackupInformation -SqlInstance NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
                ($output.Count) -gt 0 | Should -Be $true
                $true -in ($Output.IsVerified) | Should -Be $false
                ($null -ne $WarnVar) | Should -Be $True
            }
        }
        Context "Input without IsVerified member" {
            It "Should add IsVerified when validation fails" {
                $BackupHistory = Import-Clixml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
                $BackupHistory = $BackupHistory | Format-DbaBackupInformation
                $BackupHistory | ForEach-Object {
                    $PSItem.PSObject.Properties.Remove("IsVerified")
                }
                Mock Connect-DbaInstance -MockWith {
                    $obj = [PSCustomObject]@{
                        Name                 = "BASEName"
                        NetName              = "BASENetName"
                        ComputerName         = "BASEComputerName"
                        InstanceName         = "BASEInstanceName"
                        DomainInstanceName   = "BASEDomainInstanceName"
                        InstallDataDirectory = "BASEInstallDataDirectory"
                        ErrorLogPath         = "BASEErrorLog_{0}_{1}_{2}_Path" -f "'", '"', "]"
                        ServiceName          = "BASEServiceName"
                        VersionMajor         = 9
                        ConnectionContext    = New-Object PSObject
                    }
                    Add-Member -InputObject $obj.ConnectionContext -Name ConnectionString -MemberType NoteProperty -Value "put=an=equal=in=it"
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
                }
                Mock Get-DbaDatabase { $null }
                Mock New-DbaDirectory { $true }
                Mock Test-DbaPath { [PSCustomObject]@{
                        FilePath   = "does\not\exists"
                        FileExists = $false
                    }
                }
                Mock New-DbaDirectory { $True }
                $output = $BackupHistory | Test-DbaBackupInformation -SqlInstance NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
                ($output | Where-Object { "IsVerified" -notin $PSItem.PSObject.Properties.Name }).Count | Should -Be 0
                $output.IsVerified | Should -Not -Contain $true
                $output.IsVerified | Should -Not -Contain $null
                ($null -ne $WarnVar) | Should -Be $True
            }
        }
        Context "Multiple source dbs for restore is bad" {
            It "Should return fail as 2 origin dbs" {
                $BackupHistory = Import-Clixml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
                $BackupHistory = $BackupHistory | Format-DbaBackupInformation
                $BackupHistory[1].OriginalDatabase = 'Error'
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
                }
                Mock Get-DbaDatabase { $null }
                Mock New-DbaDirectory { $true }
                Mock Test-DbaPath { [PSCustomObject]@{
                        FilePath   = 'does\exists'
                        FileExists = $true
                    }
                }
                Mock New-DbaDirectory { $True }
                $output = $BackupHistory | Test-DbaBackupInformation -SqlInstance NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
                ($output.Count) -gt 0 | Should -Be $true
                $true -in ($Output.IsVerified) | Should -Be $False
                ($null -ne $WarnVar) | Should -Be $True
            }
        }
        Context "Fail if Destination db exists" {
            It "Should return fail if dest db exists" {
                $BackupHistory = Import-Clixml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
                $BackupHistory = $BackupHistory | Format-DbaBackupInformation
                $BackupHistory[1].OriginalDatabase = 'Error'
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
                }
                Mock Get-DbaDatabase { '1' }
                Mock New-DbaDirectory { $true }
                Mock Test-DbaPath { [PSCustomObject]@{
                        FilePath   = 'does\exists'
                        FileExists = $true
                    }
                }
                Mock New-DbaDirectory { $True }
                $output = $BackupHistory | Test-DbaBackupInformation -SqlInstance NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
                ($output.Count) -gt 0 | Should -Be $true
                $true -in ($Output.IsVerified) | Should -Be $False
                ($null -ne $WarnVar) | Should -Be $True
            }
        }
        Context "Pass if Destination db exists and WithReplace set" {
            It "Should pass if destdb exists and WithReplace specified" {
                $BackupHistory = Import-Clixml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
                $BackupHistory = $BackupHistory | Format-DbaBackupInformation
                $BackupHistory[1].OriginalDatabase = 'Error'
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
                }
                Mock Get-DbaDatabase { '1' }
                Mock New-DbaDirectory { $true }
                Mock Test-DbaPath { [PSCustomObject]@{
                        FilePath   = 'does\exists'
                        FileExists = $true
                    }
                }
                Mock New-DbaDirectory { $True }
                $output = $BackupHistory | Test-DbaBackupInformation -SqlInstance NotExist -WarningVariable warnvar -WarningAction SilentlyContinue -WithReplace
                ($output.Count) -gt 0 | Should -Be $true
                $true -in ($Output.IsVerified) | Should -Be $False
                ($null -ne $WarnVar) | Should -Be $True
            }
        }
    }
}
