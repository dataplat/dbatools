param($ModuleName = 'dbatools')

Describe "Get-XpDirTreeRestoreFile" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-XpDirTreeRestoreFile
        }
        It "Should have Path as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Mandatory:$false
        }
        It "Should have SqlInstance as a non-mandatory DbaInstanceParameter parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory PSCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
        It "Should have NoRecurse as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter NoRecurse -Type Switch -Mandatory:$false
        }
    }

    Context "Test Connection and User Rights" {
        BeforeAll {
            Mock -ModuleName $ModuleName -CommandName Test-DbaPath { $true }
            Mock -ModuleName $ModuleName -CommandName Connect-DbaInstance { throw }
        }

        It "Should throw on an invalid SQL Connection" {
            { Get-XpDirTreeRestoreFile -Path c:\dummy -SqlInstance bad\bad -EnableException } | Should -Throw
        }

        It "Should throw if SQL Server can't see the path" {
            Mock -ModuleName $ModuleName -CommandName Test-DbaPath { $false }
            Mock -ModuleName $ModuleName -CommandName Connect-DbaInstance { [Dataplat.Dbatools.Parameter.DbaInstanceParameter]"bad\bad" }
            { Get-XpDirTreeRestoreFile -Path c:\dummy -SqlInstance bad\bad -EnableException } | Should -Throw
        }
    }

    Context "Non recursive filestructure" {
        BeforeAll {
            $array = @(
                @{ subdirectory = 'full.bak'; depth = 1; file = 1 },
                @{ subdirectory = 'full2.bak'; depth = 1; file = 1 }
            )

            Mock -ModuleName $ModuleName -CommandName Connect-DbaInstance {
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
                Add-Member -InputObject $obj.ConnectionContext -Name ConnectionString -MemberType NoteProperty -Value 'put=an=equal=in=it'
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

            $results = Get-XpDirTreeRestoreFile -Path c:\temp -SqlInstance bad\bad -EnableException
        }

        It "Should return an array of 2 files" {
            $results.Count | Should -Be 2
        }

        It "Should return a file in c:\temp" {
            $results[0].Fullname | Should -BeLike 'c:\temp\*bak'
        }

        It "Should return another file in C:\temp" {
            $results[1].Fullname | Should -BeLike 'c:\temp\*bak'
        }
    }

    Context "Recursive Filestructure" {
        BeforeAll {
            $array = @(
                @{ subdirectory = 'full.bak'; depth = 1; file = 1 },
                @{ subdirectory = 'full2.bak'; depth = 1; file = 1 },
                @{ subdirectory = 'recurse'; depth = 1; file = 0 }
            )
            $array2 = @(
                @{ subdirectory = 'fulllow.bak'; depth = 1; file = 1 },
                @{ subdirectory = 'full2low.bak'; depth = 1; file = 1 }
            )

            Mock -ModuleName $ModuleName -CommandName Connect-DbaInstance {
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
                Add-Member -InputObject $obj.ConnectionContext -Name ConnectionString -MemberType NoteProperty -Value 'put=an=equal=in=it'
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

            $results = Get-XpDirTreeRestoreFile -Path c:\temp -SqlInstance bad\bad -EnableException
        }

        It "Should return array of 4 files - recursion" {
            $results.Count | Should -Be 4
        }

        It "Should return C:\temp\recurse\fulllow.bak" {
            ($results | Where-Object { $_.Fullname -eq 'C:\temp\recurse\fulllow.bak' } | Measure-Object).Count | Should -Be 1
        }

        It "Should return C:\temp\recurse\full2low.bak" {
            ($results | Where-Object { $_.Fullname -eq 'C:\temp\recurse\full2low.bak' } | Measure-Object).Count | Should -Be 1
        }

        It "Should return C:\temp\full.bak" {
            ($results | Where-Object { $_.Fullname -eq 'C:\temp\full.bak' } | Measure-Object).Count | Should -Be 1
        }

        It "Should return C:\temp\full2.bak" {
            ($results | Where-Object { $_.Fullname -eq 'C:\temp\full2.bak' } | Measure-Object).Count | Should -Be 1
        }
    }
}
