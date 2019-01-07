$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\Get-DbaDiskSpace).Parameters.Keys
        $knownParameters = 'ComputerName', 'Credential', 'Unit', 'CheckForSql', 'SqlCredential', 'ExcludeDrive', 'CheckFragmentation', 'Force', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Disks are properly retrieved" {
        $results = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME
        It "returns at least the system drive" {
            $results.Name -contains "$env:SystemDrive\" | Should Be $true
        }

        $results = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME | Where-Object Name -eq "$env:SystemDrive\"
        It "has some valid properties" {
            $results.BlockSize -gt 0 | Should Be $true
            $results.SizeInGB -gt 0 | Should Be $true
        }
    }

    Context "CheckForSql works with mount points" {
        Mock -ModuleName 'dbatools' -CommandName 'Connect-SqlInstance' -ParameterFilter { $SqlInstance -in ('MadeUpServer', 'MadeUpServer\MadeUpInstance') } -MockWith {
            $object = [PSCustomObject] @{
                Version = @{
                    Major = 13
                }
            }
            $object | Add-Member -Name 'Query' -MemberType ScriptMethod -Value {
                return @{
                    SqlDisk = @('D:\Data\')
                }
            }
            return $object
        }

        Mock -ModuleName 'dbatools' -CommandName 'Get-DbaService' -ParameterFilter { $ComputerName.ComputerName -eq 'MadeUpServer' } -MockWith {
            return @(
                @{
                    ComputerName = 'MadeUpServer'
                    ServiceName  = 'MSSQLSERVER'
                    ServiceType  = 'Engine'
                    InstanceName = 'MSSQLSERVER'
                    DisplayName  = 'SQL Server (MSSQLSERVER)'
                    StartName    = 'FAKEDOMAIN\FAKEUSER'
                    State        = 'Running'
                    StartMode    = 'Automatic'
                },
                @{
                    ComputerName = 'MadeUpServer'
                    ServiceName  = 'MSSQLSERVER$MADEUPINSTANCE'
                    ServiceType  = 'Engine'
                    InstanceName = 'MadeUpInstance'
                    DisplayName  = 'SQL Server (MSSQLSERVER)'
                    StartName    = 'FAKEDOMAIN\FAKEUSER'
                    State        = 'Running'
                    StartMode    = 'Automatic'
                }
            )
        }

        Mock -ModuleName 'dbatools' -CommandName 'Get-DbaCmObject' -ParameterFilter { $ComputerName::InputObject -eq 'MadeUpServer' -and $Query -like '*Win32_Volume*' } -MockWith {
            return @(
                @{
                    Name        = 'D:\Data\'
                    Label       = 'Log'
                    Capacity    = 32209043456
                    Freespace   = 11653545984
                    BlockSize   = 65536
                    FileSystem  = 'NTFS'
                    DriveType   = 3
                    DriveLetter = ''
                },
                @{
                    Name        = 'C:\'
                    Label       = 'OS'
                    Capacity    = 32209043456
                    Freespace   = 11653545984
                    BlockSize   = 4096
                    FileSystem  = 'NTFS'
                    DriveType   = 2
                    DriveLetter = 'C:'
                }
            )
        }

        It -Skip "SQL Server drive is found in there somewhere" {
            $results = Get-DbaDiskSpace -ComputerName 'MadeUpServer' -CheckForSql -EnableException
            $true | Should -BeIn $results.IsSqlDisk
        }

        Assert-MockCalled -ModuleName 'dbatools' -CommandName 'Get-DbaCmObject' -Times 0
        Assert-MockCalled -ModuleName 'dbatools' -CommandName 'Get-DbaService' -Times 0
        Assert-MockCalled -ModuleName 'dbatools' -CommandName 'Connect-SqlInstance' -Times 0
    }

    Context "CheckForSql returns IsSqlDisk property with a value (likely false)" {
        Mock -ModuleName 'dbatools' -CommandName 'Get-DbaCmObject' -ParameterFilter { $Query -like '*Win32_Volume*' } -MockWith {
            return @(
                @{
                    Name        = 'D:\Data\'
                    Label       = 'Log'
                    Capacity    = 32209043456
                    Freespace   = 11653545984
                    BlockSize   = 65536
                    FileSystem  = 'NTFS'
                    DriveType   = 3
                    DriveLetter = ''
                },
                @{
                    Name        = 'C:\'
                    Label       = 'OS'
                    Capacity    = 32209043456
                    Freespace   = 11653545984
                    BlockSize   = 4096
                    FileSystem  = 'NTFS'
                    DriveType   = 2
                    DriveLetter = 'C:'
                },
                @{
                    Name        = 'T:\'
                    Label       = 'Data'
                    Capacity    = 32209043456
                    Freespace   = 11653545984
                    BlockSize   = 4096
                    FileSystem  = 'NTFS'
                    DriveType   = 2
                    DriveLetter = 'T:'
                }
            )
        }

        It "SQL Server drive is not found in there somewhere" {
            $results = Get-DbaDiskSpace -ComputerName $env:COMPUTERNAME -CheckForSql -WarningAction SilentlyContinue
            $false | Should BeIn $results.IsSqlDisk
        }
    }
}