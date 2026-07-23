#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbPartitionFunction",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/New-DbaDbPartitionFunction.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Name",
                "InputParameterType",
                "RangeType",
                "RangeValues",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        $dbBasic = "dbatoolsci_newpf_$random"
        $dbPipe1 = "dbatoolsci_newpf_p1_$random"
        $dbPipe2 = "dbatoolsci_newpf_p2_$random"
        $allDatabases = @($dbBasic, $dbPipe1, $dbPipe2)
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $allDatabases

        $intType = New-Object Microsoft.SqlServer.Management.Smo.DataType([Microsoft.SqlServer.Management.Smo.SqlDataType]::Int)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $allDatabases -Confirm:$false -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Gates the create and changes nothing" {
            $splatWhatIf = @{
                SqlInstance        = $InstanceSingle
                Database           = $dbBasic
                Name               = "pfWhatIf"
                InputParameterType = $intType
                RangeType          = [Microsoft.SqlServer.Management.Smo.RangeType]::Right
                RangeValues        = @(1, 100, 1000)
                WhatIf             = $true
            }
            New-DbaDbPartitionFunction @splatWhatIf
            $created = Get-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbBasic -PartitionFunction "pfWhatIf" -ErrorAction SilentlyContinue
            $created | Should -BeNullOrEmpty
        }
    }

    Context "Command behavior" {
        It "Creates a partition function via -SqlInstance and re-emits the decorated object" {
            $splatBasic = @{
                SqlInstance        = $InstanceSingle
                Database           = $dbBasic
                Name               = "pfBasic"
                InputParameterType = $intType
                RangeType          = [Microsoft.SqlServer.Management.Smo.RangeType]::Right
                RangeValues        = @(1, 100, 1000)
                EnableException    = $true
                Confirm            = $false
            }
            $result = New-DbaDbPartitionFunction @splatBasic
            $result.Name | Should -Be "pfBasic"
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $dbBasic
            # 3 boundaries with RANGE RIGHT => 4 partitions.
            $result.NumberOfPartitions | Should -Be 4
            (Get-DbaDbPartitionFunction -SqlInstance $InstanceSingle -Database $dbBasic -PartitionFunction "pfBasic").Name | Should -Be "pfBasic"
        }

        It "Creates a function in multiple piped databases (N in, N out)" {
            $intTypeLocal = New-Object Microsoft.SqlServer.Management.Smo.DataType([Microsoft.SqlServer.Management.Smo.SqlDataType]::Int)
            $results = Get-DbaDatabase -SqlInstance $InstanceSingle -Database $dbPipe1, $dbPipe2 |
                New-DbaDbPartitionFunction -Name "pfPipe" -InputParameterType $intTypeLocal -RangeType Right -RangeValues @(10, 20) -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            $results.Name | Sort-Object -Unique | Should -Be "pfPipe"
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Name               = "pfNeither"
                InputParameterType = $intType
                RangeValues        = @(1)
                Confirm            = $false
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "warnNeither"
            }
            $results = New-DbaDbPartitionFunction @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Requires non-empty -RangeValues" {
            $splatNoValues = @{
                SqlInstance        = $InstanceSingle
                Database           = $dbBasic
                Name               = "pfNoValues"
                InputParameterType = $intType
                RangeValues        = @()
                Confirm            = $false
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "warnNoValues"
            }
            $results = New-DbaDbPartitionFunction @splatNoValues
            $warnNoValues | Should -BeLike "*at least one boundary value*"
            $results | Should -BeNullOrEmpty
        }
    }
}
