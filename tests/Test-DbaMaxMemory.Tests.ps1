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
                # deterministic failure: without the mock this attempted a REAL connection to the
                # environment-dependent name "ABC" (resolvable on some networks, slow DNS timeout
                # on others)
                Mock Connect-DbaInstance -MockWith { throw "connection failed" }
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
                # the command only queries services on Windows; on Linux/macOS it hardcodes
                # InstanceCount 1 and never calls Get-DbaService
                if ($IsLinux -or $IsMacOS) {
                    Assert-MockCalled Get-DbaService -Scope It -Times 0 -Exactly
                } else {
                    Assert-MockCalled Get-DbaService -Scope It -Times 1
                }
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
                # deterministic memory figures - the warning path still calls Get-DbaMaxMemory,
                # and an unmocked call against the fake "ABC" server would depend on live state
                Mock Get-DbaMaxMemory -MockWith {
                    return @{ Total = 8192; MaxValue = 2147483647 }
                }
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

            It "Should return a warning" -Skip:($IsLinux -or $IsMacOS) {
                # Windows-only: on Linux/macOS the command never queries services, so the
                # component-detection warning path cannot execute at all.
                $result = Test-DbaMaxMemory -SqlInstance "ABC" -WarningVariable WarnVar -WarningAction SilentlyContinue
                $WarnVar | Should -BeLike "*The memory calculation may be inaccurate as the following SQL components have also been detected*"
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # Read-only analysis command - no server state is changed, so a live instance is all that
        # is needed. Compute once and reuse across the shape/algorithm assertions. try/finally
        # restores the EnableException default to its pre-suite state (existence AND value) even
        # if the analysis call throws - a blind Remove would drop a pre-existing default.
        $hadEnableException = $PSDefaultParameterValues.ContainsKey("*-Dba*:EnableException")
        if ($hadEnableException) { $priorEnableException = $PSDefaultParameterValues["*-Dba*:EnableException"] }
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            $result = Test-DbaMaxMemory -SqlInstance $TestConfig.InstanceSingle
        } finally {
            if ($hadEnableException) {
                $PSDefaultParameterValues["*-Dba*:EnableException"] = $priorEnableException
            } else {
                $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            }
        }
    }

    Context "Analyzing a live instance" {
        It "Returns one object carrying exactly the documented property set" {
            $result | Should -Not -BeNullOrEmpty
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "InstanceCount", "Total", "MaxValue", "RecommendedValue", "Server")
            # Compare-Object catches both missing AND extra (undocumented) properties.
            Compare-Object -ReferenceObject $expectedProps -DifferenceObject $result.PSObject.Properties.Name | Should -BeNullOrEmpty
        }

        It "Types the memory figures as integers and keeps the SMO Server reference" {
            $result.Total | Should -BeOfType System.Int32
            $result.MaxValue | Should -BeOfType System.Int32
            $result.RecommendedValue | Should -BeOfType System.Int32
            $result.InstanceCount | Should -BeGreaterThan 0
            $result.Server | Should -BeOfType Microsoft.SqlServer.Management.Smo.Server
        }

        It "Maps the identity columns from the connected Server object" {
            # ComputerName/InstanceName/SqlInstance are sourced from the SMO Server's
            # ComputerName/ServiceName/DomainInstanceName respectively - assert the mapping, not
            # just that the columns are non-null.
            $result.ComputerName | Should -Be $result.Server.ComputerName
            $result.InstanceName | Should -Be $result.Server.ServiceName
            $result.SqlInstance | Should -Be $result.Server.DomainInstanceName
        }

        It "Reports Total and MaxValue straight from Get-DbaMaxMemory" {
            # Total (physical memory) is stable hardware state, so its equality holds across the
            # two reads. MaxValue is instance-global MUTABLE configuration that other suites
            # (Set-DbaMaxMemory) legitimately change on the shared instance between the analysis
            # call and this re-read - assert only its invariant, not a cross-moment equality.
            $memory = Get-DbaMaxMemory -SqlInstance $TestConfig.InstanceSingle
            $result.Total | Should -Be ([int]$memory.Total)
            $result.MaxValue | Should -BeGreaterThan 0
        }

        It "Derives InstanceCount from running Engine services with a fallback of 1" {
            # Invariant only: exactly reproducing the service-discovery count here races the
            # shared host's topology between the BeforeAll analysis call and this re-count (and
            # exact-count coverage already lives in the mocked unit tests above). The documented
            # fallback floor of 1 is the stable live contract; the algorithm test below is
            # self-consistent against whatever count the analysis call itself observed.
            $result.InstanceCount | Should -BeGreaterOrEqual 1
        }

        It "Computes RecommendedValue by the documented Kehayias algorithm" {
            # Re-derive the recommendation from the returned Total and InstanceCount (both pinned to
            # their sources in the tests above) using the exact source arithmetic and confirm the
            # command's value matches - this pins the memory math against any drift in the port.
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

        It "Sets the default view to exactly the seven analysis columns, hiding the Server handle" {
            # Select-DefaultView shows the analysis columns and excludes the SMO Server handle.
            $defaultProps = $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedView = @("ComputerName", "InstanceName", "SqlInstance", "InstanceCount", "Total", "MaxValue", "RecommendedValue")
            Compare-Object -ReferenceObject $expectedView -DifferenceObject $defaultProps | Should -BeNullOrEmpty
        }

        It "Returns one object per value supplied to -SqlInstance" {
            # Read-only, so passing the same instance twice simply exercises the foreach loop and
            # must yield one analysis object per element.
            $multi = @(Test-DbaMaxMemory -SqlInstance @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle))
            $multi.Count | Should -Be 2
        }
    }
}