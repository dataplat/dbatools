#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaInstanceAuditSpecification",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/New-DbaInstanceAuditSpecification.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "AuditSpecification",
                "Audit",
                "AuditActionType",
                "InputObject",
                "Enable",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Types AuditActionType as the SMO enum array so the accepted values never drift" {
            (Get-Command $CommandName).Parameters["AuditActionType"].ParameterType.ToString() |
                Should -Be "Microsoft.SqlServer.Management.Smo.AuditActionType[]"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        # A SQL Server audit accepts at most ONE server audit specification (1:1). Every
        # spec-creating test therefore gets its OWN parent audit, and the multi-record leg pipes
        # two DISTINCT servers rather than several specs onto one audit.
        $instanceA = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $instanceB = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
        $pathA = (Get-DbaDefaultPath -SqlInstance $instanceA).Data
        $pathB = (Get-DbaDefaultPath -SqlInstance $instanceB).Data

        $auditSingleName = "dbatoolsci_audsingle_$random"
        $auditEnableName = "dbatoolsci_auden_$random"
        $auditMultiName  = "dbatoolsci_audmulti_$random"

        $null = New-DbaInstanceAudit -SqlInstance $instanceA -Audit $auditSingleName -DestinationType File -FilePath $pathA
        $null = New-DbaInstanceAudit -SqlInstance $instanceA -Audit $auditEnableName -DestinationType File -FilePath $pathA
        $null = New-DbaInstanceAudit -SqlInstance $instanceA -Audit $auditMultiName -DestinationType File -FilePath $pathA
        $null = New-DbaInstanceAudit -SqlInstance $instanceB -Audit $auditMultiName -DestinationType File -FilePath $pathB

        $specSingleName = "dbatoolsci_specsingle_$random"
        $specEnableName = "dbatoolsci_specen_$random"
        $specMultiName  = "dbatoolsci_specmulti_$random"
        $specWhatIfName = "dbatoolsci_specwi_$random"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # No Remove-DbaInstanceAuditSpecification yet (pending row): tear down through SMO. Disable
        # before dropping - an enabled specification cannot be dropped, nor an enabled audit.
        foreach ($srv in $instanceA, $instanceB) {
            $srv.ServerAuditSpecifications.Refresh()
            foreach ($name in $specSingleName, $specEnableName, $specMultiName, $specWhatIfName) {
                $existing = $srv.ServerAuditSpecifications[$name]
                if ($existing) {
                    if ($existing.Enabled) { $existing.Disable() }
                    $existing.Drop()
                }
            }
            $srv.Audits.Refresh()
            foreach ($name in $auditSingleName, $auditEnableName, $auditMultiName) {
                $audit = $srv.Audits[$name]
                if ($audit) {
                    if ($audit.Enabled) { $audit.Disable() }
                    $audit.Drop()
                }
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and creates nothing" {
            # WhatIf text is HOST-DIRECT: *>&1 / 6>&1 capture nothing in-process, so a transcript is
            # the reliable in-Pester capture. The asserted string is verbatim from the signed spec.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_whatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance        = $instanceA
                AuditSpecification = $specWhatIfName
                Audit              = $auditSingleName
                AuditActionType    = "AuditChangeGroup"
                WhatIf             = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                New-DbaInstanceAuditSpecification @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $instanceA.DomainInstanceName
                $expectedAction = "Creating server audit specification $specWhatIfName for audit $auditSingleName"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAction`" on target `"$expectedTarget`""))
            } finally {
                # Stop-Transcript writes to the error stream when the host is no longer transcribing,
                # and Pester counts that as a failure - swallow it in a catch instead.
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen.
            $existing = Get-DbaInstanceAuditSpecification -SqlInstance $instanceA | Where-Object Name -eq $specWhatIfName
            $existing | Should -BeNullOrEmpty
        }
    }

    Context "Command behavior" {
        It "Creates a single specification via -SqlInstance, disabled by default, decorated like Get-DbaInstanceAuditSpecification" {
            $splatCreate = @{
                SqlInstance        = $instanceA
                AuditSpecification = $specSingleName
                Audit              = $auditSingleName
                AuditActionType    = "AuditChangeGroup"
                EnableException    = $true
                Confirm            = $false
            }
            $result = New-DbaInstanceAuditSpecification @splatCreate
            $result.Name | Should -Be $specSingleName
            $result.AuditName | Should -Be $auditSingleName
            # Specifications are created disabled by default (matching the server) - -Enable was not bound.
            $result.Enabled | Should -Be $false
            # Decoration parity with Get-DbaInstanceAuditSpecification so Get -> New -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty

            $readBack = Get-DbaInstanceAuditSpecification -SqlInstance $instanceA | Where-Object Name -eq $specSingleName
            $readBack.AuditName | Should -Be $auditSingleName
        }

        It "Creates a specification already enabled with -Enable (Enable is a method call, not a property set)" {
            $splatEnable = @{
                SqlInstance        = $instanceA
                AuditSpecification = $specEnableName
                Audit              = $auditEnableName
                AuditActionType    = "BackupRestoreGroup"
                Enable             = $true
                EnableException    = $true
                Confirm            = $false
            }
            $result = New-DbaInstanceAuditSpecification @splatEnable
            $result.Enabled | Should -Be $true
            $readBack = Get-DbaInstanceAuditSpecification -SqlInstance $instanceA | Where-Object Name -eq $specEnableName
            $readBack.Enabled | Should -Be $true
        }

        It "Processes multiple piped servers, each resolving its own instance (N in, N out)" {
            # Mandatory multi-record leg. A single -Audit cannot fan out to several specs on one
            # server (the 1:1 audit:spec rule), so the real cross-record dimension is the Server[]
            # feeder: two distinct servers, each creating its own spec on its own like-named audit.
            $results = $instanceA, $instanceB |
                New-DbaInstanceAuditSpecification -AuditSpecification $specMultiName -Audit $auditMultiName -AuditActionType AuditChangeGroup -Confirm:$false -EnableException
            ($results | Measure-Object).Count | Should -Be 2
            ($results.SqlInstance | Sort-Object -Unique | Measure-Object).Count | Should -Be 2
            (Get-DbaInstanceAuditSpecification -SqlInstance $instanceA).Name | Should -Contain $specMultiName
            (Get-DbaInstanceAuditSpecification -SqlInstance $instanceB).Name | Should -Contain $specMultiName
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                AuditSpecification = "dbatoolsci_none_$random"
                Audit              = $auditSingleName
                Confirm            = $false
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "warnNeither"
            }
            $results = New-DbaInstanceAuditSpecification @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Requires the parent audit via -Audit" {
            $splatNoAudit = @{
                SqlInstance        = $instanceA
                AuditSpecification = "dbatoolsci_noaudit_$random"
                Confirm            = $false
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "warnAudit"
            }
            $results = New-DbaInstanceAuditSpecification @splatNoAudit
            $warnAudit | Should -BeLike "*You must specify the parent audit via -Audit*"
            $results | Should -BeNullOrEmpty
        }

        It "Throws a terminating error with -EnableException when the parent audit does not exist" {
            $splatThrow = @{
                SqlInstance        = $instanceA
                AuditSpecification = "dbatoolsci_orphan_$random"
                Audit              = "dbatoolsci_missingaudit_$random"
                AuditActionType    = "AuditChangeGroup"
                Confirm            = $false
                EnableException    = $true
            }
            { New-DbaInstanceAuditSpecification @splatThrow } | Should -Throw
        }
    }
}
