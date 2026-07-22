#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaInstanceAudit",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaInstanceAudit.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Audit",
                "InputObject",
                "DestinationType",
                "Disable",
                "Enable",
                "EnableException",
                "FilePath",
                "Filter",
                "MaximumFileSize",
                "MaximumFileSizeUnit",
                "MaximumFiles",
                "MaximumRolloverFiles",
                "NewName",
                "OnFailure",
                "QueueDelay",
                "ReserveDiskSpace"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Exposes Enable, Disable and ReserveDiskSpace as switches, not [bool] (dbatools house style)" {
            foreach ($switchName in "Enable", "Disable", "ReserveDiskSpace") {
                (Get-Command $CommandName).Parameters[$switchName].ParameterType.Name | Should -Be "SwitchParameter"
            }
        }

        It "Types MaximumRolloverFiles as Int64 and MaximumFiles as Int32 (the spec typing trap)" {
            (Get-Command $CommandName).Parameters["MaximumRolloverFiles"].ParameterType.Name | Should -Be "Int64"
            (Get-Command $CommandName).Parameters["MaximumFiles"].ParameterType.Name | Should -Be "Int32"
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

        $auditEnabledName = "dbatoolsci_setauditen_$random"   # the distinguishing leg: alter while ENABLED
        $auditDisabledName = "dbatoolsci_setauditdis_$random"
        $auditStateName = "dbatoolsci_setauditstate_$random"
        $auditPipeName = "dbatoolsci_setauditpipe_$random"
        $auditRenameName = "dbatoolsci_setauditren_$random"
        $auditRenamedName = "dbatoolsci_setauditren2_$random"
        $auditWhatIfName = "dbatoolsci_setauditwi_$random"

        $allAuditNames = @($auditEnabledName, $auditDisabledName, $auditStateName, $auditPipeName, $auditRenameName, $auditRenamedName, $auditWhatIfName)

        # Setup fixtures via the sibling New-DbaInstanceAudit (already shipped). The ENABLED audit is the
        # one that proves the Disable/Alter/Enable state machine - an alter against it fails server-side
        # unless the cmdlet sequences STATE=OFF itself.
        $null = New-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditEnabledName -DestinationType File -FilePath $auditPath -QueueDelay 1000 -Enable -Confirm:$false
        $null = New-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditDisabledName -DestinationType File -FilePath $auditPath -QueueDelay 1000 -Confirm:$false
        $null = New-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditStateName -DestinationType File -FilePath $auditPath -Confirm:$false
        $null = New-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditPipeName -DestinationType File -FilePath $auditPath -QueueDelay 1000 -Confirm:$false
        $null = New-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditRenameName -DestinationType File -FilePath $auditPath -Confirm:$false
        $null = New-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditWhatIfName -DestinationType File -FilePath $auditPath -QueueDelay 1000 -Confirm:$false

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # There is no Remove-DbaInstanceAudit yet (pending row), so tear down through SMO: disable
        # before dropping because an enabled audit holds its file.
        $cleanupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
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

    Context "The Disable/Alter/Enable state machine (distinguishing leg)" {
        It "Alters an option on an ENABLED audit and leaves it enabled - STATE=OFF is sequenced by the cmdlet, not SMO" {
            # This is the signature gotcha of the row: ALTER SERVER AUDIT requires STATE=OFF and SMO
            # does NOT sequence it. A cmdlet that just calls Alter() on an enabled audit fails server-side.
            # The audit must come back ENABLED (state preserved, neither -Enable nor -Disable bound) with
            # the new option applied.
            $splatAlter = @{
                SqlInstance     = $InstanceSingle
                Audit           = $auditEnabledName
                QueueDelay      = 5000
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaInstanceAudit @splatAlter
            $result.Name | Should -Be $auditEnabledName
            $result.QueueDelay | Should -Be 5000
            # State PRESERVED across the disable/alter/enable sequence - the audit is still running.
            $result.IsEnabled | Should -Be $true

            $readBack = Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditEnabledName
            $readBack.QueueDelay | Should -Be 5000
            $readBack.Enabled | Should -Be $true
        }
    }

    Context "State switches" {
        It "Enables a disabled audit with -Enable" {
            $result = Set-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditStateName -Enable -Confirm:$false -EnableException
            $result.IsEnabled | Should -Be $true
            (Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditStateName).Enabled | Should -Be $true
        }

        It "Disables an enabled audit with -Disable" {
            # $auditStateName was enabled by the previous test.
            $result = Set-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditStateName -Disable -Confirm:$false -EnableException
            $result.IsEnabled | Should -Be $false
            (Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditStateName).Enabled | Should -Be $false
        }

        It "Rejects -Enable and -Disable together (they are mutually exclusive)" {
            $splatBoth = @{
                SqlInstance     = $InstanceSingle
                Audit           = $auditDisabledName
                Enable          = $true
                Disable         = $true
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnBoth"
            }
            $results = Set-DbaInstanceAudit @splatBoth
            $warnBoth | Should -BeLike "*cannot specify both -Enable and -Disable*"
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Rename is a separate DDL round-trip" {
        It "Renames an audit via -NewName" {
            $result = Set-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditRenameName -NewName $auditRenamedName -Confirm:$false -EnableException
            $result.Name | Should -Be $auditRenamedName
            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditRenamedName | Should -Not -BeNullOrEmpty
            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditRenameName | Should -BeNullOrEmpty
        }
    }

    Context "Pipeline input" {
        It "Accepts an SMO Audit piped in from Get-DbaInstanceAudit (InputObject is the getCounterpart type)" {
            $result = Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditPipeName | Set-DbaInstanceAudit -QueueDelay 4000 -Confirm:$false -EnableException
            $result.Name | Should -Be $auditPipeName
            $result.QueueDelay | Should -Be 4000
            (Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditPipeName).QueueDelay | Should -Be 4000
        }
    }

    Context "WhatIf support" {
        It "Emits BOTH designed ShouldProcess strings and changes nothing" {
            # -WhatIf must show the alter AND the rename (two non-atomic operations) and leave the server
            # untouched. WhatIf text is HOST-DIRECT: *>&1 / 6>&1 capture nothing in-process, so a
            # transcript is the reliable in-Pester capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_setwhatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                Audit       = $auditWhatIfName
                QueueDelay  = 9000
                NewName     = "dbatoolsci_setauditwi_never_$random"
                WhatIf      = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaInstanceAudit @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $expectedAlter = "Altering server audit $auditWhatIfName"
                $expectedRename = "Renaming server audit $auditWhatIfName to dbatoolsci_setauditwi_never_$random"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAlter`" on target `"$expectedTarget`""))
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedRename`" on target `"$expectedTarget`""))
            } finally {
                # Stop-Transcript writes to the error stream when the host is no longer transcribing,
                # and Pester counts that as a failure - swallow it in a catch instead.
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and neither side effect happened: option unchanged, old name still present, new name absent.
            $unchanged = Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit $auditWhatIfName
            $unchanged | Should -Not -BeNullOrEmpty
            $unchanged.QueueDelay | Should -Be 1000
            Get-DbaInstanceAudit -SqlInstance $InstanceSingle -Audit "dbatoolsci_setauditwi_never_$random" | Should -BeNullOrEmpty
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Audit           = $auditDisabledName
                QueueDelay      = 2000
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaInstanceAudit @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Requires -Audit when -SqlInstance is specified" {
            $splatNoAudit = @{
                SqlInstance     = $InstanceSingle
                QueueDelay      = 2000
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnAudit"
            }
            $results = Set-DbaInstanceAudit @splatNoAudit
            $warnAudit | Should -BeLike "*Audit is required when SqlInstance is specified*"
            $results | Should -BeNullOrEmpty
        }

        It "Reports a requested audit that does not exist and continues" {
            $splatMissing = @{
                SqlInstance     = $InstanceSingle
                Audit           = "dbatoolsci_setauditmissing_$random"
                QueueDelay      = 2000
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnMissing"
            }
            $results = Set-DbaInstanceAudit @splatMissing
            $warnMissing | Should -BeLike "*does not exist*"
            $results | Should -BeNullOrEmpty
        }
    }
}
