#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaMaxMemory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        Context "Validate input arguments" {
            It "No SQL Server Windows service is running on the host" {
                { Test-DbaMaxMemory -SqlInstance "ABC" -EnableException } | Should -Throw
            }

            It "SqlInstance parameter is empty throws an exception" {
                Mock Get-DbaMaxMemory -MockWith { return $null }
                { Test-DbaMaxMemory -SqlInstance "" } | Should -Throw
            }
        }

        Context "Validate functionality - Single Instance" {
            BeforeAll {
                Mock Connect-DbaInstance -MockWith {
                    "nothing"
                }

                Mock Get-DbaMaxMemory -MockWith {
                    New-Object PSObject -Property @{
                        ComputerName = "SQL2016"
                        InstanceName = "MSSQLSERVER"
                        SqlInstance  = "SQL2016"
                        Total        = 4096
                        MaxValue     = 2147483647
                    }
                }

                Mock Get-DbaService -MockWith {
                    New-Object PSObject -Property @{
                        InstanceName = "foo"
                        State        = "Running"
                        ServiceType  = "Engine"
                    }
                }
            }

            It "Connect to SQL Server" {
                Mock Get-DbaMaxMemory -MockWith { }

                $result = Test-DbaMaxMemory -SqlInstance "ABC"

                Assert-MockCalled Connect-DbaInstance -Scope It -Times 1
                Assert-MockCalled Get-DbaService -Scope It -Times 1
                Assert-MockCalled Get-DbaMaxMemory -Scope It -Times 1
            }

            It "Connect to SQL Server and retrieve the Max Server Memory setting" {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ MaxValue = 2147483647 }
                }

                (Test-DbaMaxMemory -SqlInstance "ABC").MaxValue | Should -Be 2147483647
            }

            It "Calculate recommended memory - Single instance, Total 4GB, Expected 2GB, Reserved 2GB (.5x Memory)" {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 4096 }
                }

                $result = Test-DbaMaxMemory -SqlInstance "ABC"
                $result.InstanceCount | Should -Be 1
                $result.RecommendedValue | Should -Be 2048
            }

            It "Calculate recommended memory - Single instance, Total 6GB, Expected 3GB, Reserved 3GB (Iterations => 2x 8GB)" {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 6144 }
                }

                $result = Test-DbaMaxMemory -SqlInstance "ABC"
                $result.InstanceCount | Should -Be 1
                $result.RecommendedValue | Should -Be 3072
            }

            It "Calculate recommended memory - Single instance, Total 8GB, Expected 5GB, Reserved 3GB (Iterations => 2x 8GB)" {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 8192 }
                }

                $result = Test-DbaMaxMemory -SqlInstance "ABC"
                $result.InstanceCount | Should -Be 1
                $result.RecommendedValue | Should -Be 5120
            }

            It "Calculate recommended memory - Single instance, Total 16GB, Expected 11GB, Reserved 5GB (Iterations => 4x 8GB)" {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 16384 }
                }

                $result = Test-DbaMaxMemory -SqlInstance "ABC"
                $result.InstanceCount | Should -Be 1
                $result.RecommendedValue | Should -Be 11264
            }

            It "Calculate recommended memory - Single instance, Total 18GB, Expected 13GB, Reserved 5GB (Iterations => 1x 16GB, 3x 8GB)" {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 18432 }
                }

                $result = Test-DbaMaxMemory -SqlInstance "ABC"
                $result.InstanceCount | Should -Be 1
                $result.RecommendedValue | Should -Be 13312
            }

            It "Calculate recommended memory - Single instance, Total 32GB, Expected 25GB, Reserved 7GB (Iterations => 2x 16GB, 4x 8GB)" {
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 32768 }
                }

                $result = Test-DbaMaxMemory -SqlInstance "ABC"
                $result.InstanceCount | Should -Be 1
                $result.RecommendedValue | Should -Be 25600
            }
        }

    }
}

Describe $CommandName -Tag UnitTests {
    InModuleScope dbatools {
        Context "Raise warning when another component detected" {
            BeforeAll {
                Mock Get-DbaService -MockWith {
                    @{
                        InstanceName = "foo"
                        State        = "Running"
                        ServiceType  = "SSRS"
                    },
                    @{
                        InstanceName = "foo"
                        State        = "Running"
                        ServiceType  = "Engine"
                    }
                }
                Mock Connect-DbaInstance {
                    $obj = [PSCustomObject]@{
                        Name                 = "BASEName"
                        NetName              = "BASENetName"
                        ComputerName         = "BASEComputerName"
                        InstanceName         = "BASEInstanceName"
                        DomainInstanceName   = "BASEDomainInstanceName"
                        InstallDataDirectory = "BASEInstallDataDirectory"
                        ErrorLogPath         = "BASEErrorLog_{0}_{1}_{2}_Path" -f "'", '"', "]"
                        ServiceName          = "BASEServiceName"
                        VersionMajor         = 12
                        ConnectionContext    = New-Object PSObject
                    }
                    Add-Member -InputObject $obj.ConnectionContext -Name ConnectionString  -MemberType NoteProperty -Value "put=an=equal=in=it"
                    $obj.PSObject.TypeNames.Clear()
                    $obj.PSObject.TypeNames.Add("Microsoft.SqlServer.Management.Smo.Server")
                    return $obj
                }
            }

            It "Should return a warning" {
                $result = Test-DbaMaxMemory -SqlInstance "ABC" -WarningVariable WarnVar -WarningAction SilentlyContinue
                $WarnVar | Should -BeLike "*The memory calculation may be inaccurate as the following SQL components have also been detected*"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        # Read-only analysis command - no server state is changed, so a live instance is all that
        # is needed. Compute once and reuse across the shape/algorithm assertions.
        $result = Test-DbaMaxMemory -SqlInstance $TestConfig.InstanceSingle
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Analyzing a live instance" {
        It "Returns one object carrying every documented property" {
            $result | Should -Not -BeNullOrEmpty
            foreach ($prop in "ComputerName", "InstanceName", "SqlInstance", "InstanceCount", "Total", "MaxValue", "RecommendedValue", "Server") {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It "Types the memory figures as integers and keeps the SMO Server reference" {
            $result.Total | Should -BeOfType System.Int32
            $result.MaxValue | Should -BeOfType System.Int32
            $result.RecommendedValue | Should -BeOfType System.Int32
            $result.InstanceCount | Should -BeGreaterThan 0
            $result.Server | Should -BeOfType Microsoft.SqlServer.Management.Smo.Server
        }

        It "Reports MaxValue matching the instance's current max server memory" {
            # MaxValue comes straight from Get-DbaMaxMemory, so the two must agree.
            $current = (Get-DbaMaxMemory -SqlInstance $TestConfig.InstanceSingle).MaxValue
            $result.MaxValue | Should -Be ([int]$current)
        }

        It "Computes RecommendedValue by the documented Kehayias algorithm" {
            # Re-derive the recommendation from the SAME returned Total and InstanceCount using the
            # exact source arithmetic and confirm the command's value matches - this pins the memory
            # math against any drift in the port.
            $total = $result.Total
            $instanceCount = $result.InstanceCount
            if ($total -ge 4096) {
                $reserve = 1
                $currentCount = $total
                while ($currentCount / 4096 -gt 0) {
                    if ($currentCount -gt 16384) {
                        $reserve += 1
                        $currentCount += -8192
                    } else {
                        $reserve += 1
                        $currentCount += -4096
                    }
                }
                $recommendedMax = [int]($total - ($reserve * 1024))
            } else {
                $recommendedMax = $total * .5
            }
            $recommendedMax = $recommendedMax / $instanceCount
            $result.RecommendedValue | Should -Be ([int]$recommendedMax)
        }

        It "Excludes Server from the default view but keeps it accessible" {
            # Select-DefaultView keeps the analysis columns visible and hides the SMO Server handle.
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $defaultProps | Should -Contain "RecommendedValue"
            $defaultProps | Should -Not -Contain "Server"
        }

        It "Returns one object per value supplied to -SqlInstance" {
            # Read-only, so passing the same instance twice simply exercises the foreach loop and
            # must yield one analysis object per element.
            $multi = @(Test-DbaMaxMemory -SqlInstance @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle))
            $multi.Count | Should -Be 2
        }
    }
}