#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaWsfcResourceType",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Characterization tests (2026-07-06, Track A TA-072): pin the observed behavior of the live
    # implementation ahead of the C# port. InstanceMulti2 is the FCI network name (sqlcluster);
    # querying it reaches the WSFC (wincluster in the lab, sqlnode1/sqlnode2 as members).
    #
    # root\MSCluster CIM requires domain auth. This gate must run via PSDirect (Invoke-Command
    # -VMName workstation -Credential lab\cl) or a domain-authenticated session on the workstation;
    # the SSH-key gate (administrator@10.0.1.20) yields Access Denied from CIM and returns empty.
    #
    # Lab observation (2026-07-06): the lab WSFC (wincluster) exposes 43 resource types including
    # SQL Server, SQL Server Agent, SQL Server Availability Group, SQL Server FILESTREAM Share.
    # ClusterName="wincluster", ClusterFqdn="wincluster.lab.local".
    # ClusterName and ClusterFqdn are injected as NoteProperty members via Add-Member -Force.
    # Name and DllName are native CIM properties from MSCluster_ResourceType.
    # RequiredDependencyTypes is a System.String[] (empty array when no dependencies required;
    # 7 of 43 resource types have at least one required dependency type).
    # No -Name filter parameter exists on this command (unlike Get-DbaWsfcResourceGroup).
    Context "When querying the lab failover cluster" {
        BeforeAll {
            # No fixture setup -- read-only command. EnableException is NOT set globally:
            # inner helpers (Get-DbaWsfcCluster, Get-DbaCmObject) warn rather than throw when
            # CIM auth fails, so setting EnableException via PSDefaultParameterValues would
            # incorrectly turn those warnings into terminating errors.
            $typeResults = @(Get-DbaWsfcResourceType -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Returns resource types for a WSFC cluster" {
            # characterization: the lab WSFC exposes at least 10 resource types
            $typeResults.Count | Should -BeGreaterOrEqual 10
        }

        It "Returns MSCluster_ResourceType CIM instances" {
            # characterization: output is a raw CIM instance with injected NoteProperty members
            $typeResults[0].PSObject.TypeNames[0] | Should -Match "MSCluster_ResourceType"
        }

        It "Carries ClusterName as a NoteProperty member added by Add-Member" {
            # characterization: ClusterName is injected via Add-Member -Force, not a native CIM property
            $prop = $typeResults[0].PSObject.Properties["ClusterName"]
            $prop | Should -Not -BeNullOrEmpty
            $prop.MemberType | Should -Be "NoteProperty"
        }

        It "Carries ClusterFqdn as a NoteProperty member added by Add-Member" {
            # characterization: ClusterFqdn is injected via Add-Member -Force, not a native CIM property
            $prop = $typeResults[0].PSObject.Properties["ClusterFqdn"]
            $prop | Should -Not -BeNullOrEmpty
            $prop.MemberType | Should -Be "NoteProperty"
        }

        It "Reports cluster identity on each resource type" {
            $typeResults[0].ClusterName | Should -Not -BeNullOrEmpty
            $typeResults[0].ClusterFqdn | Should -Match "^$([regex]::Escape($typeResults[0].ClusterName))\."
        }

        It "Reports Name as a native CIM property (not NoteProperty)" {
            # characterization: Name comes directly from MSCluster_ResourceType, not injected
            $prop = $typeResults[0].PSObject.Properties["Name"]
            $prop | Should -Not -BeNullOrEmpty
            $prop.MemberType | Should -Not -Be "NoteProperty"
        }

        It "Reports DllName as a native CIM property (not NoteProperty)" {
            # characterization: DllName comes directly from MSCluster_ResourceType, not injected
            $prop = $typeResults[0].PSObject.Properties["DllName"]
            $prop | Should -Not -BeNullOrEmpty
            $prop.MemberType | Should -Not -Be "NoteProperty"
        }

        It "Reports a non-empty Name on every returned resource type" {
            foreach ($rt in $typeResults) {
                $rt.Name | Should -Not -BeNullOrEmpty
            }
        }

        It "Reports a non-empty DllName on most returned resource types" {
            # characterization: most resource types have an implementing DLL; MSMQ and MSMQTriggers
            # are an exception -- their DllName is null (characterization: current behavior, do not
            # "fix" without a surface-diff decision). Verify at least the majority carry a DllName.
            $withDll = $typeResults | Where-Object { $PSItem.DllName }
            $withDll.Count | Should -BeGreaterThan ($typeResults.Count / 2)
        }

        It "Reports RequiredDependencyTypes as String array or null on every resource type" {
            # characterization: RequiredDependencyTypes is System.String[] (possibly empty) for most
            # resource types; MSMQ and MSMQTriggers return null (not empty array). Both are valid
            # characterization values -- do not "fix" without a surface-diff decision.
            $withRdt = $typeResults | Where-Object { $null -ne $PSItem.RequiredDependencyTypes }
            foreach ($rt in $withRdt) {
                $rt.RequiredDependencyTypes.GetType().Name | Should -Be "String[]"
            }
        }

        It "Includes SQL Server resource types in the cluster" {
            # characterization: a SQL FCI cluster exposes SQL-specific resource types
            $sqlTypes = $typeResults | Where-Object Name -match "SQL Server"
            $sqlTypes.Count | Should -BeGreaterOrEqual 1
        }

        It "Includes a SQL Server resource type with its FCI DLL" {
            # characterization: the SQL Server resource type is implemented by sqsrvres.dll
            $sqlServerType = $typeResults | Where-Object Name -eq "SQL Server"
            $sqlServerType | Should -Not -BeNullOrEmpty
            $sqlServerType.DllName | Should -Be "sqsrvres.dll"
        }

        It "Has at least one resource type with required dependency types" {
            # characterization: 7 of 43 resource types in the lab have RequiredDependencyTypes
            $withDeps = $typeResults | Where-Object { $PSItem.RequiredDependencyTypes.Count -gt 0 }
            $withDeps.Count | Should -BeGreaterOrEqual 1
        }
    }

    Context "When using pipeline input" {
        BeforeAll {
            $allTypes = @(Get-DbaWsfcResourceType -ComputerName $TestConfig.InstanceMulti2)
        }

        It "Accepts pipeline input and returns the same resource type count" {
            # characterization: ComputerName accepts DbaInstanceParameter[] via ValueFromPipeline
            $pipelineResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcResourceType)
            $pipelineResults.Count | Should -Be $allTypes.Count
        }

        It "Pipeline result carries the same ClusterName as direct call" {
            $pipelineResults = @($TestConfig.InstanceMulti2 | Get-DbaWsfcResourceType)
            $pipelineResults[0].ClusterName | Should -Be $allTypes[0].ClusterName
        }
    }

    Context "When the target computer cannot be reached" {
        It "Warns and returns nothing for a non-existent host" {
            # characterization: Get-DbaWsfcResourceType calls Get-DbaWsfcCluster then Get-DbaCmObject.
            # When neither can connect, both inner helpers emit warnings and return empty;
            # the outer command produces no output.
            $splatBad = @{
                ComputerName    = "dbatoolsci_nohost"
                WarningVariable = "warnings"
                WarningAction   = "SilentlyContinue"
                ErrorAction     = "SilentlyContinue"
            }
            $unreachableResult = Get-DbaWsfcResourceType @splatBad
            $unreachableResult | Should -BeNullOrEmpty
            "$warnings" | Should -Match "Unable to find a connection to the target system"
        }
    }
}
