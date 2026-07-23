#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaCmConnection",
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
                "UseWindowsCredentials",
                "OverrideExplicitCredential",
                "DisabledConnectionTypes",
                "DisableBadCredentialCache",
                "DisableCimPersistence",
                "DisableCredentialAutoRegister",
                "EnableCredentialFailover",
                "WindowsCredentialsAreBad",
                "CimWinRMOptions",
                "CimDCOMOptions",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>

Describe $CommandName -Tag IntegrationTests {
    # Characterization context (an empty run is never green). The CIM connection cache is
    # process-local state - no lab instance required.
    Context "When registering a connection object" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $results = New-DbaCmConnection -ComputerName dbatoolsci-cmconn -OverrideExplicitCredential
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaCmConnection -ComputerName dbatoolsci-cmconn -Confirm:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns a connection object for the computer" {
            $results.ComputerName | Should -Be "dbatoolsci-cmconn"
        }

        It "Applies the requested override flag" {
            $results.OverrideExplicitCredential | Should -BeTrue
        }
    }

    # The ComputerName default is $env:COMPUTERNAME. PowerShell evaluates a typed default zero
    # times when the parameter is bound on the command line, and re-applies it before every
    # pipeline record. Because that default's converter side-effect registers a local-box
    # connection in the shared cache, the two binding paths must be distinguished: an explicit
    # bind must NOT leave a stray local-box entry, while a multi-record pipe re-applies the
    # default (local-box present) and must emit one object per element in pipeline order.
    Context "When binding ComputerName explicitly versus over the pipeline" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Clear the local-box entry first so the explicit-bind assertion below reliably
            # distinguishes: a construction-time default converter would re-register it.
            $null = Remove-DbaCmConnection -ComputerName $env:COMPUTERNAME -Confirm:$false

            # Explicit command-line bind: default evaluated zero times.
            $beforeExplicit = @(Get-DbaCmConnection).ComputerName
            $null = New-DbaCmConnection -ComputerName dbatoolsci-cmexplicit -OverrideExplicitCredential
            $afterExplicit = @(Get-DbaCmConnection).ComputerName
            $addedByExplicit = @($afterExplicit | Where-Object { $_ -notin $beforeExplicit })

            # Multi-record pipeline: default re-applied at begin (local-box registered), one
            # emitted object per element, order preserved.
            $piped = @("dbatoolsci-cmpipea", "dbatoolsci-cmpipeb") | New-DbaCmConnection -OverrideExplicitCredential
            $afterPipe = @(Get-DbaCmConnection).ComputerName
            $localBoxCached = $afterPipe -contains $env:COMPUTERNAME

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaCmConnection -ComputerName dbatoolsci-cmexplicit, dbatoolsci-cmpipea, dbatoolsci-cmpipeb -Confirm:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Registers only the explicitly bound computer, not the local-box default" {
            $addedByExplicit | Should -Be @("dbatoolsci-cmexplicit")
        }

        It "Emits one connection object per piped element in pipeline order" {
            @($piped).ComputerName | Should -Be @("dbatoolsci-cmpipea", "dbatoolsci-cmpipeb")
        }

        It "Caches every piped computer" {
            $afterPipe | Should -Contain "dbatoolsci-cmpipea"
            $afterPipe | Should -Contain "dbatoolsci-cmpipeb"
        }

        It "Re-applies the default on the pipeline path so the local-box connection is registered" {
            $localBoxCached | Should -BeTrue
        }
    }
}
