#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-XpDirTreeRestoreFile",
    $PSDefaultParameterValues = (Get-TestConfig).Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        BeforeAll {
            #mock Connect-DbaInstance { $true }
            Mock Test-DbaPath { $true }
        }

        Context "Test Connection and User Rights" {
            It "Should throw on an invalid SQL Connection" {
                #mock Test-SQLConnection {(1..12) | %{[System.Collections.ArrayList]$t += @{ConnectSuccess = $false}}}
                Mock Connect-DbaInstance { throw }
                { Get-XpDirTreeRestoreFile -Path "c:\dummy" -SqlInstance "bad\bad" -EnableException } | Should -Throw
            }
            It "Should throw if SQL Server can't see the path" {
                Mock Test-DbaPath { $false }
                Mock Connect-DbaInstance { [DbaInstanceParameter]"bad\bad" }
                { Get-XpDirTreeRestoreFile -Path "c:\dummy" -SqlInstance "bad\bad" -EnableException } | Should -Throw
            }
        }
        Context "Non recursive filestructure" {
            BeforeAll {
                $array = @(
                    @{ subdirectory = "full.bak"; depth = 1; file = 1 },
                    @{ subdirectory = "full2.bak"; depth = 1; file = 1 }
                )
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
                    Add-Member -InputObject $obj.ConnectionContext -Name ConnectionString  -MemberType NoteProperty -Value "put=an=equal=in=it"
                    Add-Member -InputObject $obj -Name Query -MemberType ScriptMethod -Value {
                        param($query)
                        if ($query -eq "EXEC master.sys.xp_dirtree 'c:\temp\',1,1;") {
                            return $array
                        }
                    }
                    $obj.PSObject.TypeNames.Clear()
                    $obj.PSObject.TypeNames.Add("Microsoft.SqlServer.Management.Smo.Server")
                    return $obj
                }
                $global:results = Get-XpDirTreeRestoreFile -Path "c:\temp" -SqlInstance "bad\bad" -EnableException
            }
            It "Should return an array of 2 files" {
                $global:results.Count | Should -Be 2
            }
            It "Should return a file in c:\temp" {
                $global:results[0].Fullname | Should -BeLike "c:\temp\*bak"
            }
            It "Should return another file in C:\temp" {
                $global:results[1].Fullname | Should -BeLike "c:\temp\*bak"
            }
        }
        Context "Recursive Filestructure" {
            BeforeAll {
                $array = @(
                    @{ subdirectory = "full.bak"; depth = 1; file = 1 },
                    @{ subdirectory = "full2.bak"; depth = 1; file = 1 },
                    @{ subdirectory = "recurse"; depth = 1; file = 0 }
                )
                $array2 = @(
                    @{ subdirectory = "fulllow.bak"; depth = 1; file = 1 },
                    @{ subdirectory = "full2low.bak"; depth = 1; file = 1 }
                )
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
                    Add-Member -InputObject $obj.ConnectionContext -Name ConnectionString  -MemberType NoteProperty -Value "put=an=equal=in=it"
                    Add-Member -InputObject $obj -Name Query -MemberType ScriptMethod -Value {
                        param($query)
                        if ($query -eq "EXEC master.sys.xp_dirtree 'c:\temp\recurse\',1,1;") {
                            return $array2
                        }
                        if ($query -eq "EXEC master.sys.xp_dirtree 'c:\temp\',1,1;") {
                            return $array
                        }
                    }
                    $obj.PSObject.TypeNames.Clear()
                    $obj.PSObject.TypeNames.Add("Microsoft.SqlServer.Management.Smo.Server")
                    return $obj
                }

                $global:results = Get-XpDirTreeRestoreFile -Path "c:\temp" -SqlInstance "bad\bad" -EnableException
            }
            It "Should return array of 4 files - recursion" {
                $global:results.Count | Should -Be 4
            }
            It "Should return C:\temp\recurse\fulllow.bak" {
                ($global:results | Where-Object Fullname -eq "C:\temp\recurse\fulllow.bak" | Measure-Object).Count | Should -Be 1
            }
            It "Should return C:\temp\recurse\full2low.bak" {
                ($global:results | Where-Object Fullname -eq "C:\temp\recurse\full2low.bak" | Measure-Object).Count | Should -Be 1
            }
            It "Should return C:\temp\full.bak" {
                ($global:results | Where-Object Fullname -eq "C:\temp\full.bak" | Measure-Object).Count | Should -Be 1
            }
            It "Should return C:\temp\full2.bak" {
                ($global:results | Where-Object Fullname -eq "C:\temp\full2.bak" | Measure-Object).Count | Should -Be 1
            }
        }
    }
}