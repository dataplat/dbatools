#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
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
                $output = $BackupHistory | Test-DbaBackupInformation -SqlInstance NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
                $global:dbatoolsciOutput = $output
                ($output.Count) -gt 0 | Should -Be $true
                "False" -in ($Output.IsVerified) | Should -Be $False
                ($null -ne $WarnVar) | Should -Be $True
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
        Context "Output validation" {
            AfterAll {
                $global:dbatoolsciOutput = $null
            }

            It "Should have the expected properties" {
                $expectedProperties = @(
                    "BackupSetId",
                    "CheckpointLsn",
                    "ComputerName",
                    "Database",
                    "DatabaseBackupLsn",
                    "DeviceType",
                    "Duration",
                    "End",
                    "FileList",
                    "FirstLsn",
                    "FullName",
                    "InstanceName",
                    "IsCopyOnly",
                    "IsVerified",
                    "LastLsn",
                    "LastRecoveryForkGUID",
                    "OriginalDatabase",
                    "OriginalFileList",
                    "OriginalFullName",
                    "Path",
                    "Position",
                    "Software",
                    "SoftwareVersionMajor",
                    "SqlInstance",
                    "Start",
                    "TotalSize",
                    "Type",
                    "UserName"
                )
                $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
                Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
            }

            It "Should have IsVerified set on all output objects" {
                $global:dbatoolsciOutput | ForEach-Object {
                    $PSItem.PSObject.Properties.Name | Should -Contain "IsVerified"
                }
            }

            It "Should have accurate .OUTPUTS documentation" {
                $help = Get-Help Test-DbaBackupInformation -Full
                $help.returnValues.returnValue.type.name | Should -Match "Dataplat\.Dbatools\.Database\.BackupHistory"
            }
        }
    }
}