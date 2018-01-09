$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    InModuleScope dbatools {
        Context "Everything as it should" {
            $BackupHistory = Import-CliXml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
            $BackupHistory = $BackupHistory | Format-DbaBackupInformation
            Mock Connect-SqlInstance -MockWith {
                $obj = [PSCustomObject]@{
                    Name                 = 'BASEName'
                    NetName              = 'BASENetName'
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
                        @{ "Name"         = "master"
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

            Mock New-DbaSqlDirectory {$true}
            Mock Test-DbaSqlPath { [pscustomobject]@{
                    FilePath   = 'does\exists'
                    FileExists = $true
                }
            }
            Mock New-DbaSqlDirectory {$True}
            It "Should pass as all systems Green" {
                $output = $BackupHistory | Test-DbaBackupInformation -SqlServer NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
                ($output.Count) -gt 0 | Should be $true
                $false -in ($Output.IsVerified) | Should be $False
                ($null -ne $WarnVar) | Should be $True
            }
        }
        Context "Not being able to see backups is bad" {
            $BackupHistory = Import-CliXml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
            $BackupHistory = $BackupHistory | Format-DbaBackupInformation
            Mock Connect-SqlInstance -MockWith {
                $obj = [PSCustomObject]@{
                    Name                 = 'BASEName'
                    NetName              = 'BASENetName'
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
                        @{ "Name"         = "master"
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
            Mock New-DbaSqlDirectory {$true}
            Mock Test-DbaSqlPath { [pscustomobject]@{
                    FilePath   = 'does\not\exists'
                    FileExists = $false
                }
            }
            Mock New-DbaSqlDirectory {$True}
            It "Should return fail as backup files don't exist" {
                $output = $BackupHistory | Test-DbaBackupInformation -SqlServer NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
                ($output.Count) -gt 0 | Should be $true
                $true -in ($Output.IsVerified) | Should be $false
                ($null -ne $WarnVar) | Should be $True
            }
        }
        Context "Multiple source dbs for restore is bad" {
            $BackupHistory = Import-CliXml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
            $BackupHistory = $BackupHistory | Format-DbaBackupInformation
            $BackupHistory[1].OriginalDatabase = 'Error'
            Mock Connect-SqlInstance -MockWith {
                $obj = [PSCustomObject]@{
                    Name                 = 'BASEName'
                    NetName              = 'BASENetName'
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
                        @{ "Name"         = "master"
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
            Mock New-DbaSqlDirectory {$true}
            Mock Test-DbaSqlPath { [pscustomobject]@{
                    FilePath   = 'does\exists'
                    FileExists = $true
                }
            }
            Mock New-DbaSqlDirectory {$True}
            It "Should return fail as 2 origin dbs" {
                $output = $BackupHistory | Test-DbaBackupInformation -SqlServer NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
                ($output.Count) -gt 0 | Should be $true
                $true -in ($Output.IsVerified) | Should be $False
                ($null -ne $WarnVar) | Should be $True
            }
        }
        Context "Fail if Destination db exists" {
            $BackupHistory = Import-CliXml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
            $BackupHistory = $BackupHistory | Format-DbaBackupInformation
            $BackupHistory[1].OriginalDatabase = 'Error'
            Mock Connect-SqlInstance -MockWith {
                $obj = [PSCustomObject]@{
                    Name                 = 'BASEName'
                    NetName              = 'BASENetName'
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
                        @{ "Name"         = "master"
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
            Mock New-DbaSqlDirectory {$true}
            Mock Test-DbaSqlPath { [pscustomobject]@{
                    FilePath   = 'does\exists'
                    FileExists = $true
                }
            }
            Mock New-DbaSqlDirectory {$True}
            It "Should return fail if dest db exists" {
                $output = $BackupHistory | Test-DbaBackupInformation -SqlServer NotExist -WarningVariable warnvar -WarningAction SilentlyContinue
                ($output.Count) -gt 0 | Should be $true
                $true -in ($Output.IsVerified) | Should be $False
                ($null -ne $WarnVar) | Should be $True
            }
        }
        Context "Pass if Destination db exists and WithReplace set" {
            $BackupHistory = Import-CliXml $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\CleanFormatDbaInformation.xml
            $BackupHistory = $BackupHistory | Format-DbaBackupInformation
            $BackupHistory[1].OriginalDatabase = 'Error'
            Mock Connect-SqlInstance -MockWith {
                $obj = [PSCustomObject]@{
                    Name                 = 'BASEName'
                    NetName              = 'BASENetName'
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
                        @{ "Name"         = "master"
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
            Mock New-DbaSqlDirectory {$true}
            Mock Test-DbaSqlPath { [pscustomobject]@{
                    FilePath   = 'does\exists'
                    FileExists = $true
                }
            }
            Mock New-DbaSqlDirectory {$True}
            It "Should pass if destdb exists and WithReplace specified" {
                $output = $BackupHistory | Test-DbaBackupInformation -SqlServer NotExist -WarningVariable warnvar -WarningAction SilentlyContinue -WithReplace
                ($output.Count) -gt 0 | Should be $true
                $true -in ($Output.IsVerified) | Should be $False
                ($null -ne $WarnVar) | Should be $True
            }
        }
    }
}