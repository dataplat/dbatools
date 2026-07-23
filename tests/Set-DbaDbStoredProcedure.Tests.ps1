#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbStoredProcedure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDbStoredProcedure.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Schema",
                "Name",
                "Definition",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        $dbName = "dbatoolsci_setproc_$random"
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $dbName

        # Seed the procedures the alter legs act on. Invoke-DbaQuery keeps setup independent of New-DbaDbStoredProcedure.
        $seed = @(
            "CREATE PROCEDURE dbo.spEdit AS SELECT 1 AS x;"
            "CREATE PROCEDURE dbo.spPipe1 AS SELECT 1 AS x;"
            "CREATE PROCEDURE dbo.spPipe2 AS SELECT 1 AS x;"
            "CREATE PROCEDURE dbo.spWhatIf AS SELECT 1 AS x;"
        )
        foreach ($ddl in $seed) {
            $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbName -Query $ddl
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $dbName -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Gates the alter and changes nothing" {
            # The ShouldProcess text is emitted from the module-scoped hop body and is host-direct, so the
            # distinguishing assertion is that the side effect did NOT happen - the body is unchanged.
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                Database    = $dbName
                Name        = "spWhatIf"
                Definition  = "SELECT 2 AS y"
                WhatIf      = $true
            }
            Set-DbaDbStoredProcedure @splatWhatIf

            $after = Get-DbaDbStoredProcedure -SqlInstance $InstanceSingle -Database $dbName -Name "spWhatIf"
            # The distinguishing assertion: the body still holds the original text, not the -WhatIf replacement.
            $after.TextBody | Should -BeLike "*SELECT 1 AS x*"
            $after.TextBody | Should -Not -BeLike "*SELECT 2 AS y*"
        }
    }

    Context "Command behavior" {
        It "Alters a procedure body via -SqlInstance and re-emits the decorated object" {
            $splatEdit = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbName
                Name            = "spEdit"
                Definition      = "SELECT 42 AS answer"
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbStoredProcedure @splatEdit
            $result.Name | Should -Be "spEdit"
            # Decoration parity with Get-DbaDbStoredProcedure so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $dbName
            # The new body is live server-side.
            (Get-DbaDbStoredProcedure -SqlInstance $InstanceSingle -Database $dbName -Name "spEdit").TextBody.Trim() | Should -Be "SELECT 42 AS answer"
        }

        It "Alters multiple piped procedures (N in, N out)" {
            # Multi-record piped leg. Two procedures piped in from Get-DbaDbStoredProcedure must both come back
            # altered, each resolving its own parent.
            $results = Get-DbaDbStoredProcedure -SqlInstance $InstanceSingle -Database $dbName -Name "spPipe1", "spPipe2" |
                Set-DbaDbStoredProcedure -Definition "SELECT 99 AS n" -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            foreach ($name in "spPipe1", "spPipe2") {
                (Get-DbaDbStoredProcedure -SqlInstance $InstanceSingle -Database $dbName -Name $name).TextBody.Trim() | Should -Be "SELECT 99 AS n"
            }
        }
    }

    Context "Guards" {
        It "Refuses a CLR procedure with a clear message and does not alter" {
            # A CLR procedure has no editable text body. Deploying a real signed assembly is impractical here, so the
            # guard is exercised by piping an in-memory SMO StoredProcedure whose ImplementationType is SqlClr - the
            # command reads ImplementationType directly (not a caught SMO exception), so the object need not exist server-side.
            $db = Get-DbaDatabase -SqlInstance $InstanceSingle -Database $dbName
            $clrProc = New-Object Microsoft.SqlServer.Management.Smo.StoredProcedure -ArgumentList $db, "spFakeClr", "dbo"
            $clrProc.ImplementationType = [Microsoft.SqlServer.Management.Smo.ImplementationType]::SqlClr

            $splatClr = @{
                Definition      = "SELECT 1 AS x"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnClr"
            }
            $results = $clrProc | Set-DbaDbStoredProcedure @splatClr
            $warnClr | Should -BeLike "*CLR procedure*"
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Name            = "spEdit"
                Definition      = "SELECT 1 AS x"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaDbStoredProcedure @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }
    }
}
