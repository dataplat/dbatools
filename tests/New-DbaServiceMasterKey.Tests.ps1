#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaServiceMasterKey",
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
                "SecurePassword",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    # NOTE ON COVERAGE: New-DbaServiceMasterKey targets the master database SPECIFICALLY - it is a
    # thin wrapper that forwards to New-DbaDbMasterKey -Database master inside a ShouldProcess gate.
    # Its delegate refuses to create a second key when master already carries one (Stop-Function
    # "Master key already exists in the master database on <server>" -Continue: warns, emits nothing).
    # master on the shared InstanceSingle already carries a database master key that this suite does
    # not own and must never drop (dropping a key we cannot restore could orphan dependent objects).
    # So the LIVE distinguishing leg here is the real already-exists guard against that key (real
    # behavior on a live instance, no mock - the seal technique /gomanager blessed on #75), plus the
    # WhatIf gate that proves ShouldProcess short-circuits before the delegate ever runs. Only when
    # master unexpectedly has NO key does BeforeAll manufacture a baseline (and AfterAll drop exactly
    # that one), so the distinguishing leg always RUNS regardless of instance pre-state and no
    # pre-existing key is ever touched.
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        $existingKey = Get-DbaDbMasterKey -SqlInstance $server -Database master
        $script:createdBaseline = $false
        if (-not $existingKey) {
            $baselinePassword = ConvertTo-SecureString "dbatools.IO.baseline" -AsPlainText -Force
            $null = New-DbaDbMasterKey -SqlInstance $server -Database master -SecurePassword $baselinePassword -Confirm:$false
            $script:createdBaseline = $true
        }

        $script:originalCreateDate = (Get-DbaDbMasterKey -SqlInstance $server -Database master).CreateDate

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # Only ever remove a key THIS suite manufactured; a pre-existing master key is left untouched.
        if ($script:createdBaseline) {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database master -Confirm:$false
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Against a master database that already has a master key (live InstanceSingle)" {
        It "warns 'already exists', emits no MasterKey, and does not clobber the existing key" {
            $splatExisting = @{
                SqlInstance     = $TestConfig.InstanceSingle
                SecurePassword  = (ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force)
                WarningVariable = "warnExisting"
                WarningAction   = "SilentlyContinue"
                Confirm         = $false
            }
            $result = @(New-DbaServiceMasterKey @splatExisting)

            # the delegate refuses when a key exists, so nothing reaches the pipeline
            $result.Count | Should -Be 0

            # the real already-exists guard fired; strip the [timestamp][function] Write-Message prefix
            $payloads = $warnExisting | ForEach-Object { $PSItem.Message -replace "^(\[[^\]]*\]\s*)+", "" }
            ($payloads -join "`n") | Should -Match "Master key already exists in the master database"

            # side effect that must NOT happen: the pre-existing key is untouched (no drop+recreate)
            $afterKey = Get-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database master
            $afterKey | Should -Not -BeNullOrEmpty
            $afterKey.CreateDate | Should -Be $script:originalCreateDate
        }
    }

    Context "WhatIf gates the delegate before it runs" {
        It "emits nothing, does not invoke the delegate (no already-exists warning), and leaves the key untouched" {
            $splatWhatIf = @{
                SqlInstance     = $TestConfig.InstanceSingle
                SecurePassword  = (ConvertTo-SecureString "dbatools.IO" -AsPlainText -Force)
                WarningVariable = "warnWhatIf"
                WarningAction   = "SilentlyContinue"
                WhatIf          = $true
            }
            $result = @(New-DbaServiceMasterKey @splatWhatIf)
            $result.Count | Should -Be 0

            # ShouldProcess("Creating new master key") returns $false under -WhatIf, so the nested
            # New-DbaDbMasterKey is never called and its already-exists guard never fires - the
            # distinguishing difference from the real run above.
            $payloads = $warnWhatIf | ForEach-Object { $PSItem.Message -replace "^(\[[^\]]*\]\s*)+", "" }
            ($payloads -join "`n") | Should -Not -Match "Master key already exists"

            $afterKey = Get-DbaDbMasterKey -SqlInstance $TestConfig.InstanceSingle -Database master
            $afterKey.CreateDate | Should -Be $script:originalCreateDate
        }
    }
}