#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaInstanceAuditSpecification",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Remove-DbaInstanceAuditSpecification.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "AuditSpecification",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Has no -Force because an audit specification is a leaf object (deliberate asymmetry with Remove-DbaInstanceAudit)" {
            (Get-Command $CommandName).Parameters.Keys | Should -Not -Contain "Force"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $instance = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $path = (Get-DbaDefaultPath -SqlInstance $instance).Data

        # A SQL Server audit accepts at most ONE server audit specification (1:1), so every spec gets its
        # OWN parent audit. The cross-record leg pipes several specs (each on its own audit) off one server
        # through Get-DbaInstanceAuditSpecification.
        $auditEnabledName = "dbatoolsci_audenabled_$random"
        $auditDisabledName = "dbatoolsci_auddisabled_$random"
        $auditWhatIfName  = "dbatoolsci_audwi_$random"
        $auditPipe1Name   = "dbatoolsci_audpipe1_$random"
        $auditPipe2Name   = "dbatoolsci_audpipe2_$random"

        foreach ($auditName in $auditEnabledName, $auditDisabledName, $auditWhatIfName, $auditPipe1Name, $auditPipe2Name) {
            $null = New-DbaInstanceAudit -SqlInstance $instance -Audit $auditName -DestinationType File -FilePath $path
        }

        $specEnabledName  = "dbatoolsci_specen_$random"
        $specDisabledName = "dbatoolsci_specdis_$random"
        $specWhatIfName   = "dbatoolsci_specwi_$random"
        $specPipe1Name    = "dbatoolsci_specpipe1_$random"
        $specPipe2Name    = "dbatoolsci_specpipe2_$random"

        # The distinguishing spec is created ENABLED: dropping it succeeds only because the cmdlet disables
        # it first (DROP SERVER AUDIT SPECIFICATION needs STATE=OFF).
        $null = New-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specEnabledName -Audit $auditEnabledName -AuditActionType AuditChangeGroup -Enable -Confirm:$false
        $null = New-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specDisabledName -Audit $auditDisabledName -AuditActionType AuditChangeGroup -Confirm:$false
        $null = New-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specWhatIfName -Audit $auditWhatIfName -AuditActionType AuditChangeGroup -Confirm:$false
        $null = New-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specPipe1Name -Audit $auditPipe1Name -AuditActionType AuditChangeGroup -Confirm:$false
        $null = New-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specPipe2Name -Audit $auditPipe2Name -AuditActionType AuditChangeGroup -Confirm:$false

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Best-effort SMO teardown of anything the tests did not already drop; disable before dropping.
        $instance.ServerAuditSpecifications.Refresh()
        foreach ($name in $specEnabledName, $specDisabledName, $specWhatIfName, $specPipe1Name, $specPipe2Name) {
            $existing = $instance.ServerAuditSpecifications[$name]
            if ($existing) {
                if ($existing.Enabled) { $existing.Disable() }
                $existing.Drop()
            }
        }
        $instance.Audits.Refresh()
        foreach ($name in $auditEnabledName, $auditDisabledName, $auditWhatIfName, $auditPipe1Name, $auditPipe2Name) {
            $audit = $instance.Audits[$name]
            if ($audit) {
                if ($audit.Enabled) { $audit.Disable() }
                $audit.Drop()
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and drops nothing" {
            # WhatIf text is HOST-DIRECT: a transcript is the reliable in-Pester capture. The asserted
            # string is verbatim from the signed spec's shouldProcessTargets.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_rmspecwi_$random.txt"
            $splatWhatIf = @{
                SqlInstance        = $instance
                AuditSpecification = $specWhatIfName
                WhatIf             = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Remove-DbaInstanceAuditSpecification @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $instance.DomainInstanceName
                $expectedAction = "Removing server audit specification $specWhatIfName"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAction`" on target `"$expectedTarget`""))
            } finally {
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen: the specification still exists.
            $existing = Get-DbaInstanceAuditSpecification -SqlInstance $instance | Where-Object Name -eq $specWhatIfName
            $existing | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command behavior" {
        It "Drops an ENABLED specification (proves disable-before-drop) and emits the pre-drop snapshot" {
            # THE distinguishing leg: DROP SERVER AUDIT SPECIFICATION needs STATE=OFF, which SMO does not
            # sequence, so a naive port throws on an enabled spec. A green result is the proof.
            $result = Remove-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specEnabledName -EnableException -Confirm:$false
            $result.Name | Should -Be $specEnabledName
            # Decoration parity with Get-DbaInstanceAuditSpecification.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.SqlInstance  | Should -Not -BeNullOrEmpty
            $readBack = Get-DbaInstanceAuditSpecification -SqlInstance $instance | Where-Object Name -eq $specEnabledName
            $readBack | Should -BeNullOrEmpty
        }

        It "Drops a disabled specification via -SqlInstance/-AuditSpecification" {
            $null = Remove-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specDisabledName -EnableException -Confirm:$false
            $readBack = Get-DbaInstanceAuditSpecification -SqlInstance $instance | Where-Object Name -eq $specDisabledName
            $readBack | Should -BeNullOrEmpty
        }

        It "Drops multiple piped specifications from Get-DbaInstanceAuditSpecification (N in, N out)" {
            # Cross-record leg on the InputObject feeder.
            $results = Get-DbaInstanceAuditSpecification -SqlInstance $instance |
                Where-Object Name -in $specPipe1Name, $specPipe2Name |
                Remove-DbaInstanceAuditSpecification -Confirm:$false -EnableException
            ($results | Measure-Object).Count | Should -Be 2
            $stillThere = Get-DbaInstanceAuditSpecification -SqlInstance $instance | Where-Object Name -in $specPipe1Name, $specPipe2Name
            $stillThere | Should -BeNullOrEmpty
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                AuditSpecification = "dbatoolsci_none_$random"
                Confirm            = $false
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "warnNeither"
            }
            $results = Remove-DbaInstanceAuditSpecification @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues when a requested specification does not exist" {
            $splatMissing = @{
                SqlInstance        = $instance
                AuditSpecification = "dbatoolsci_missing_$random"
                Confirm            = $false
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "warnMissing"
            }
            $results = Remove-DbaInstanceAuditSpecification @splatMissing
            $warnMissing | Should -BeLike "*does not exist*"
            $results | Should -BeNullOrEmpty
        }
    }
}
