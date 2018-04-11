$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Connect-SqlInstance.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    InModuleScope dbatools {
        #mock Connect-SqlInstance { $true }
        mock Test-DbaSqlPath { $true }

        Context "Test Connection and User Rights" {
            It "Should throw on an invalid SQL Connection" {
                #mock Test-SQLConnection {(1..12) | %{[System.Collections.ArrayList]$t += @{ConnectSuccess = $false}}}
                Mock Connect-SqlInstance { throw }
                { Get-XpDirTreeRestoreFile -path c:\dummy -SqlInstance bad\bad -EnableException $true } | Should Throw
            }
            It "Should throw if SQL Server can't see the path" {
                Mock Test-DbaSqlPath { $false }
                Mock Connect-SqlInstance { [DbaInstanceParameter]"bad\bad" }
                { Get-XpDirTreeRestoreFile -path c:\dummy -SqlInstance bad\bad -EnableException $true } | Should Throw
            }
        }
        Context "Non recursive filestructure" {
            $array = (@{ subdirectory = 'full.bak'; depth = 1; file = 1 },
                @{ subdirectory = 'full2.bak'; depth = 1; file = 1 })
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
                    if ($query -eq "EXEC master.sys.xp_dirtree 'c:\temp\',1,1;") {
                        return $array
                    }
                }
                $obj.PSObject.TypeNames.Clear()
                $obj.PSObject.TypeNames.Add("Microsoft.SqlServer.Management.Smo.Server")
                return $obj
            }
            $results = Get-XpDirTreeRestoreFile -path c:\temp -SqlInstance bad\bad -EnableException $true
            It "Should return an array of 2 files" {
                $results.count | Should Be 2
            }
            It "Should return a file in c:\temp" {
                $results[0].Fullname | Should BeLike 'c:\temp\*bak'
            }
            It "Should return another file in C:\temp" {
                $results[1].Fullname | Should BeLike 'c:\temp\*bak'
            }
        }
        Context "Recursive Filestructure" {
            $array = (@{ subdirectory = 'full.bak'; depth = 1; file = 1 },
                @{ subdirectory = 'full2.bak'; depth = 1; file = 1 },
                @{ subdirectory = 'recurse'; depth = 1; file = 0 })
            $array2 = (@{ subdirectory = 'fulllow.bak'; depth = 1; file = 1 },
                @{ subdirectory = 'full2low.bak'; depth = 1; file = 1 })
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


            $results = Get-XpDirTreeRestoreFile -path c:\temp -SqlInstance bad\bad -EnableException $true
            It "Should return array of 4 files - recursion" {
                $results.count | Should Be 4
            }
            It "Should return C:\temp\recurse\fulllow.bak" {
                ($results | Where-Object { $_.Fullname -eq 'C:\temp\recurse\fulllow.bak' } | measure-Object).count | Should be 1
            }
            It "Should return C:\temp\recurse\fulllow.bak" {
                ($results | Where-Object { $_.Fullname -eq 'C:\temp\recurse\full2low.bak' } | measure-Object).count | Should be 1
            }
            It "Should return C:\temp\recurse\fulllow.bak" {
                ($results | Where-Object { $_.Fullname -eq 'C:\temp\full.bak' } | measure-Object).count | Should be 1
            }
            It "Should return C:\temp\recurse\fulllow.bak" {
                ($results | Where-Object { $_.Fullname -eq 'C:\temp\full2.bak' } | measure-Object).count | Should be 1
            }
        }
    }
}
