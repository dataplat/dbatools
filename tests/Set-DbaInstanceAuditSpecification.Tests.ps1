#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaInstanceAuditSpecification",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaInstanceAuditSpecification.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "AuditSpecification",
                "Audit",
                "AddAction",
                "RemoveAction",
                "InputObject",
                "Enable",
                "Disable",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Types AddAction and RemoveAction as the SMO enum array so the accepted values never drift" {
            (Get-Command $CommandName).Parameters["AddAction"].ParameterType.ToString() |
                Should -Be "Microsoft.SqlServer.Management.Smo.AuditActionType[]"
            (Get-Command $CommandName).Parameters["RemoveAction"].ParameterType.ToString() |
                Should -Be "Microsoft.SqlServer.Management.Smo.AuditActionType[]"
        }

        It "Has no -NewName because Name is ReadOnlyAfterCreation on an audit specification" {
            (Get-Command $CommandName).Parameters.Keys | Should -Not -Contain "NewName"
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

        # A SQL Server audit accepts at most ONE server audit specification (1:1), so every spec gets
        # its OWN parent audit. Repointing needs an empty destination audit; the cross-record leg pipes
        # several specs (each on its own audit) off one server through Get-DbaInstanceAuditSpecification.
        $auditAlterName   = "dbatoolsci_audalter_$random"
        $auditActionName  = "dbatoolsci_audaction_$random"
        $auditFromName    = "dbatoolsci_audfrom_$random"
        $auditToName      = "dbatoolsci_audto_$random"
        $auditToggleName  = "dbatoolsci_audtoggle_$random"
        $auditWhatIfName  = "dbatoolsci_audwi_$random"
        $auditPipe1Name   = "dbatoolsci_audpipe1_$random"
        $auditPipe2Name   = "dbatoolsci_audpipe2_$random"

        foreach ($auditName in $auditAlterName, $auditActionName, $auditFromName, $auditToName, $auditToggleName, $auditWhatIfName, $auditPipe1Name, $auditPipe2Name) {
            $null = New-DbaInstanceAudit -SqlInstance $instance -Audit $auditName -DestinationType File -FilePath $path
        }

        $specAlterName   = "dbatoolsci_specalter_$random"
        $specActionName  = "dbatoolsci_specaction_$random"
        $specRepointName = "dbatoolsci_specrepoint_$random"
        $specToggleName  = "dbatoolsci_spectoggle_$random"
        $specWhatIfName  = "dbatoolsci_specwi_$random"
        $specPipe1Name   = "dbatoolsci_specpipe1_$random"
        $specPipe2Name   = "dbatoolsci_specpipe2_$random"

        # The signature-gotcha spec is created ENABLED: altering it proves the cmdlet sequences
        # Disable -> Alter -> Enable itself (ALTER SERVER AUDIT SPECIFICATION needs STATE=OFF and SMO
        # does not sequence it), because the spec comes back still enabled.
        $null = New-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specAlterName -Audit $auditAlterName -AuditActionType AuditChangeGroup -Enable -Confirm:$false
        $null = New-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specActionName -Audit $auditActionName -AuditActionType AuditChangeGroup -Confirm:$false
        $null = New-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specRepointName -Audit $auditFromName -AuditActionType AuditChangeGroup -Confirm:$false
        $null = New-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specToggleName -Audit $auditToggleName -AuditActionType AuditChangeGroup -Confirm:$false
        $null = New-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specPipe1Name -Audit $auditPipe1Name -AuditActionType AuditChangeGroup -Enable -Confirm:$false
        $null = New-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specPipe2Name -Audit $auditPipe2Name -AuditActionType AuditChangeGroup -Enable -Confirm:$false

        function Get-SpecActions {
            param($ServerObject, $SpecName)
            $ServerObject.ServerAuditSpecifications.Refresh()
            $specObject = $ServerObject.ServerAuditSpecifications[$SpecName]
            $specObject.EnumAuditSpecificationDetails() | ForEach-Object { $PSItem.Action.ToString() }
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # No Remove-DbaInstanceAuditSpecification is flipped yet: tear down through SMO. Disable before
        # dropping - an enabled specification cannot be dropped, nor an enabled audit.
        $instance.ServerAuditSpecifications.Refresh()
        foreach ($name in $specAlterName, $specActionName, $specRepointName, $specToggleName, $specWhatIfName, $specPipe1Name, $specPipe2Name) {
            $existing = $instance.ServerAuditSpecifications[$name]
            if ($existing) {
                if ($existing.Enabled) { $existing.Disable() }
                $existing.Drop()
            }
        }
        $instance.Audits.Refresh()
        foreach ($name in $auditAlterName, $auditActionName, $auditFromName, $auditToName, $auditToggleName, $auditWhatIfName, $auditPipe1Name, $auditPipe2Name) {
            $audit = $instance.Audits[$name]
            if ($audit) {
                if ($audit.Enabled) { $audit.Disable() }
                $audit.Drop()
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and changes nothing" {
            # WhatIf text is HOST-DIRECT: a transcript is the reliable in-Pester capture. The asserted
            # string is verbatim from the signed spec's shouldProcessTargets.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_setspecwi_$random.txt"
            $splatWhatIf = @{
                SqlInstance        = $instance
                AuditSpecification = $specActionName
                AddAction          = "BackupRestoreGroup"
                WhatIf             = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaInstanceAuditSpecification @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $instance.DomainInstanceName
                $expectedAction = "Altering server audit specification $specActionName"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAction`" on target `"$expectedTarget`""))
            } finally {
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen: the action was not added.
            (Get-SpecActions -ServerObject $instance -SpecName $specActionName) | Should -Not -Contain "BackupRestoreGroup"
        }
    }

    Context "Command behavior" {
        It "Alters an ENABLED specification and leaves it enabled (proves Disable -> Alter -> Enable sequencing)" {
            # THE distinguishing leg: adding an action to an enabled spec requires STATE=OFF, which SMO
            # does not sequence, so a naive port throws. A green result with Enabled still true is the proof.
            $splatAlter = @{
                SqlInstance        = $instance
                AuditSpecification = $specAlterName
                AddAction          = "BackupRestoreGroup"
                EnableException    = $true
                Confirm            = $false
            }
            $result = Set-DbaInstanceAuditSpecification @splatAlter
            $result.Enabled | Should -Be $true
            $actions = Get-SpecActions -ServerObject $instance -SpecName $specAlterName
            $actions | Should -Contain "AuditChangeGroup"
            $actions | Should -Contain "BackupRestoreGroup"
            # Decoration parity with Get-DbaInstanceAuditSpecification so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.SqlInstance  | Should -Not -BeNullOrEmpty
        }

        It "Adds and removes audit action types (removes applied before adds)" {
            $splatAdd = @{
                SqlInstance        = $instance
                AuditSpecification = $specActionName
                AddAction          = "BackupRestoreGroup", "DatabaseObjectChangeGroup"
                EnableException    = $true
                Confirm            = $false
            }
            $null = Set-DbaInstanceAuditSpecification @splatAdd
            $afterAdd = Get-SpecActions -ServerObject $instance -SpecName $specActionName
            $afterAdd | Should -Contain "BackupRestoreGroup"
            $afterAdd | Should -Contain "DatabaseObjectChangeGroup"

            $splatRemove = @{
                SqlInstance        = $instance
                AuditSpecification = $specActionName
                RemoveAction       = "BackupRestoreGroup"
                EnableException    = $true
                Confirm            = $false
            }
            $null = Set-DbaInstanceAuditSpecification @splatRemove
            $afterRemove = Get-SpecActions -ServerObject $instance -SpecName $specActionName
            $afterRemove | Should -Not -Contain "BackupRestoreGroup"
            $afterRemove | Should -Contain "DatabaseObjectChangeGroup"
        }

        It "Re-points a specification to a different parent audit via -Audit" {
            $splatRepoint = @{
                SqlInstance        = $instance
                AuditSpecification = $specRepointName
                Audit              = $auditToName
                EnableException    = $true
                Confirm            = $false
            }
            $result = Set-DbaInstanceAuditSpecification @splatRepoint
            $result.AuditName | Should -Be $auditToName
            $readBack = Get-DbaInstanceAuditSpecification -SqlInstance $instance | Where-Object Name -eq $specRepointName
            $readBack.AuditName | Should -Be $auditToName
        }

        It "Enables and disables a specification via the mutually exclusive switches" {
            $enabled = Set-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specToggleName -Enable -EnableException -Confirm:$false
            $enabled.Enabled | Should -Be $true
            $disabled = Set-DbaInstanceAuditSpecification -SqlInstance $instance -AuditSpecification $specToggleName -Disable -EnableException -Confirm:$false
            $disabled.Enabled | Should -Be $false
        }

        It "Processes multiple piped specifications from Get-DbaInstanceAuditSpecification (N in, N out)" {
            # Cross-record leg on the InputObject feeder: two enabled specs piped in, both disabled.
            $results = Get-DbaInstanceAuditSpecification -SqlInstance $instance |
                Where-Object Name -in $specPipe1Name, $specPipe2Name |
                Set-DbaInstanceAuditSpecification -Disable -Confirm:$false -EnableException
            ($results | Measure-Object).Count | Should -Be 2
            $results.Enabled | Should -Not -Contain $true
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                AuditSpecification = $specActionName
                AddAction          = "AuditChangeGroup"
                Confirm            = $false
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "warnNeither"
            }
            $results = Set-DbaInstanceAuditSpecification @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Rejects -Enable and -Disable together" {
            $splatBoth = @{
                SqlInstance        = $instance
                AuditSpecification = $specToggleName
                Enable             = $true
                Disable            = $true
                Confirm            = $false
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "warnBoth"
            }
            $results = Set-DbaInstanceAuditSpecification @splatBoth
            $warnBoth | Should -BeLike "*cannot specify both -Enable and -Disable*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues when a requested specification does not exist" {
            $splatMissing = @{
                SqlInstance        = $instance
                AuditSpecification = "dbatoolsci_missing_$random"
                AddAction          = "AuditChangeGroup"
                Confirm            = $false
                WarningAction      = "SilentlyContinue"
                WarningVariable    = "warnMissing"
            }
            $results = Set-DbaInstanceAuditSpecification @splatMissing
            $warnMissing | Should -BeLike "*does not exist*"
            $results | Should -BeNullOrEmpty
        }
    }
}
