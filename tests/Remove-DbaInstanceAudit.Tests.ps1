#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaInstanceAudit",
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
                "Audit",
                "InputObject",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Exposes Force as a switch, not [bool] (dbatools house style)" {
            (Get-Command $CommandName).Parameters["Force"].ParameterType.Name | Should -Be "SwitchParameter"
        }

        It "Accepts an SMO Audit array on -InputObject from the pipeline (getCounterpart type)" {
            $inputParam = (Get-Command $CommandName).Parameters["InputObject"]
            $inputParam.ParameterType.FullName | Should -Be "Microsoft.SqlServer.Management.Smo.Audit[]"
            $inputParam.Attributes.ValueFromPipeline | Should -Contain $true
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Audit FILEPATH must be a directory that exists on the SQL host and the service account can write.
        $auditPath = (Get-DbaDefaultPath -SqlInstance $InstanceSingle).Data

        # Fixtures are created per-test in each It (drops are destructive and single-use), except the
        # names, which are declared here so AfterAll can sweep anything a failing test left behind.
        $auditEnabledName = "dbatoolsci_rmauditen_$random"     # the distinguishing leg: drop while ENABLED
        $auditMulti1Name = "dbatoolsci_rmauditm1_$random"
        $auditMulti2Name = "dbatoolsci_rmauditm2_$random"
        $auditPipeName = "dbatoolsci_rmauditpipe_$random"
        $auditDepName = "dbatoolsci_rmauditdep_$random"        # carries a dependent server audit specification
        $auditWhatIfName = "dbatoolsci_rmauditwi_$random"
        $depSpecName = "dbatoolsci_rmauditdepspec_$random"

        $allAuditNames = @($auditEnabledName, $auditMulti1Name, $auditMulti2Name, $auditPipeName, $auditDepName, $auditWhatIfName)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Sweep anything a failing test left behind, through SMO: drop the dependent specification first,
        # then disable-before-drop each audit (an enabled audit holds its file).
        $cleanupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $cleanupServer.ServerAuditSpecifications.Refresh()
        $leftoverSpec = $cleanupServer.ServerAuditSpecifications[$depSpecName]
        if ($leftoverSpec) { $leftoverSpec.Drop() }

        $cleanupServer.Audits.Refresh()
        foreach ($name in $allAuditNames) {
            $existing = $cleanupServer.Audits[$name]
            if ($existing) {
                if ($existing.Enabled) { $existing.Disable() }
                $existing.Drop()
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Disable before drop (distinguishing leg)" {
        It "Drops an ENABLED audit - DROP SERVER AUDIT requires STATE=OFF, sequenced by the cmdlet not SMO" {
            # DROP SERVER AUDIT fails server-side against a STATE=ON audit. A cmdlet that just calls Drop()
            # on an enabled audit fails; this one Disable()s it first, so the drop succeeds and the audit is gone.
            $null = New-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditEnabledName -DestinationType File -FilePath $auditPath -Enable -Confirm:$false -EnableException

            $result = Remove-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditEnabledName -Confirm:$false -EnableException
            $result.Name | Should -Be $auditEnabledName
            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditEnabledName | Should -BeNullOrEmpty
        }
    }

    Context "Multi-record drop" {
        It "Drops multiple named audits and emits one pre-drop snapshot per audit (N-in/N-out)" {
            $null = New-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditMulti1Name -DestinationType File -FilePath $auditPath -Confirm:$false -EnableException
            $null = New-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditMulti2Name -DestinationType File -FilePath $auditPath -Confirm:$false -EnableException

            $results = Remove-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditMulti1Name, $auditMulti2Name -Confirm:$false -EnableException
            $results.Count | Should -Be 2
            $results.Name | Should -Contain $auditMulti1Name
            $results.Name | Should -Contain $auditMulti2Name

            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditMulti1Name | Should -BeNullOrEmpty
            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditMulti2Name | Should -BeNullOrEmpty
        }
    }

    Context "Pipeline input" {
        It "Accepts an SMO Audit piped in from Get-DbaInstanceAudit (InputObject is the getCounterpart type)" {
            $null = New-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditPipeName -DestinationType File -FilePath $auditPath -Confirm:$false -EnableException

            $result = Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditPipeName | Remove-DbaInstanceAudit -Confirm:$false -EnableException
            $result.Name | Should -Be $auditPipeName
            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditPipeName | Should -BeNullOrEmpty
        }
    }

    Context "Dependent audit specifications (distinguishing leg)" {
        It "Refuses to drop an audit with a dependent specification without -Force, then cascades with -Force" {
            # SMO's DROP SERVER AUDIT does NOT cascade despite its doc comment - it fails while a spec
            # references the audit. The cmdlet enumerates the dependents, refuses cleanly without -Force,
            # and drops the spec first when -Force is bound.
            $null = New-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditDepName -DestinationType File -FilePath $auditPath -Confirm:$false -EnableException

            # Bind a server audit specification to the audit via SMO.
            $spec = New-Object Microsoft.SqlServer.Management.Smo.ServerAuditSpecification($InstanceSingle, $depSpecName)
            $spec.AuditName = $auditDepName
            $detail = New-Object Microsoft.SqlServer.Management.Smo.AuditSpecificationDetail([Microsoft.SqlServer.Management.Smo.AuditActionType]::FailedLoginGroup)
            $spec.AddAuditSpecificationDetail($detail)
            $spec.Create()

            # Without -Force: refuses, lists the dependent, leaves the audit in place.
            $splatNoForce = @{
                SqlInstance     = $InstanceSingle
                Audit           = $auditDepName
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnDep"
            }
            $refused = Remove-DbaInstanceAudit @splatNoForce
            $warnDep | Should -BeLike "*dependent audit specifications*"
            $warnDep | Should -BeLike "*$depSpecName*"
            $refused | Should -BeNullOrEmpty
            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditDepName | Should -Not -BeNullOrEmpty

            # With -Force: drops the specification first, then the audit.
            $forced = Remove-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditDepName -Force -Confirm:$false -EnableException
            $forced.Name | Should -Be $auditDepName
            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditDepName | Should -BeNullOrEmpty
            $InstanceSingle.ServerAuditSpecifications.Refresh()
            $InstanceSingle.ServerAuditSpecifications[$depSpecName] | Should -BeNullOrEmpty
        }
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and changes nothing" {
            $null = New-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditWhatIfName -DestinationType File -FilePath $auditPath -Confirm:$false -EnableException

            # WhatIf text is HOST-DIRECT: *>&1 / 6>&1 capture nothing in-process, so a transcript is the
            # reliable in-Pester capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_rmwhatif_$random.txt"
            try {
                Start-Transcript -Path $transcriptPath
                Remove-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditWhatIfName -WhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $expectedRemove = "Removing server audit $auditWhatIfName"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedRemove`" on target `"$expectedTarget`""))
            } finally {
                # Stop-Transcript writes to the error stream when the host is no longer transcribing,
                # and Pester counts that as a failure - swallow it in a catch instead.
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the audit is still there: the side effect did NOT happen.
            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditWhatIfName | Should -Not -BeNullOrEmpty
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Audit           = $auditWhatIfName
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Remove-DbaInstanceAudit @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Requires -Audit when -SqlInstance is specified" {
            $splatNoAudit = @{
                SqlInstance     = $InstanceSingle
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnAudit"
            }
            $results = Remove-DbaInstanceAudit @splatNoAudit
            $warnAudit | Should -BeLike "*Audit is required when SqlInstance is specified*"
            $results | Should -BeNullOrEmpty
        }

        It "Reports a requested audit that does not exist and continues" {
            $splatMissing = @{
                SqlInstance     = $InstanceSingle
                Audit           = "dbatoolsci_rmauditmissing_$random"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnMissing"
            }
            $results = Remove-DbaInstanceAudit @splatMissing
            $warnMissing | Should -BeLike "*does not exist*"
            $results | Should -BeNullOrEmpty
        }
    }
}
