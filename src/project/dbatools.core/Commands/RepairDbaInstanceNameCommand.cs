#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Repairs an instance's @@SERVERNAME after a Windows rename (sp_dropserver/sp_addserver
/// plus service restarts). Port of public/Repair-DbaInstanceName.ps1 (W3-082). The
/// process body rides one WHOLE-ARRAY verbatim hop per record inside a DOT-SOURCED inner
/// block (four mid-loop `Stop-Function; return` exits abandon ALL remaining instances of
/// the record, and the source has NO Test-FunctionInterrupt gate, so later pipeline
/// records still process - no latch machinery). WHOLE-ARRAY is REQUIRED here, not the
/// P2A per-element shape: the loop leaks $renamed/$needsrestart across instances (set in
/// one iteration, read by later ones - the source's own cross-instance state), which is
/// the 25a09f3 ruling's exemption clause. The leak ALSO crosses pipeline RECORDS (B
/// batch review): the __w3082State sentinel carries $renamed/$needsrestart/
/// $allsqlservices plus the engine's lastShouldProcessContinueStatus so Yes-to-All/
/// No-to-All answered in one record governs later records like the source's single
/// CommandRuntime. The Copy-family
/// `if ($Force) { $ConfirmPreference = 'none' }` begin line rides at hop top with the
/// INNER $Pscmdlet serving every gate (W3-005/W3-064 convention - no $__realCmdlet). The
/// interactive PromptForChoice AutoFix paths, the interpolated sp_dropserver/sp_addserver
/// T-SQL, the Get-Service/Stop-Service/Start-Service plumbing and the nested
/// Test-DbaInstanceName calls ride verbatim. NO WarningAction carrier (codex W3-005 r3).
/// Surface pinned by migration/baselines/Repair-DbaInstanceName.json (implicit positions
/// 0-1, SqlInstance Mandatory pos0 VFP, ConfirmImpact High).
/// </summary>
[Cmdlet(VerbsDiagnostic.Repair, "DbaInstanceName", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RepairDbaInstanceNameCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Automatically fixes rename blockers (breaks replication/mirroring).</summary>
    [Parameter]
    public SwitchParameter AutoFix { get; set; }

    /// <summary>Suppresses confirmation prompts (ConfirmPreference override).</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Cross-record state (B batch findings, hop-scope-dies-per-record class): the source
    // function scope spans the pipeline, so $renamed/$needsrestart/$allsqlservices leak
    // across records, and the inner $Pscmdlet's ShouldProcess Yes-to-All/No-to-All
    // answer must survive record boundaries too (source: ONE CommandRuntime for the
    // whole pipeline; ConfirmImpact High prompts BY DEFAULT). The sentinel carries the
    // three locals plus the runtime's lastShouldProcessContinueStatus, which the next
    // record's hop transplants into its fresh CommandRuntime (field name identical on
    // PS 5.1 and PS 7; empirically verified - [A] answered in record 1 suppresses the
    // record-2 prompt exactly like the source).
    private Hashtable? _state;

    /// <inheritdoc />
    protected override void BeginProcessing()
    {
        base.BeginProcessing();
        // C1 transplant condition: loud fail before any record if the engine field is gone.
        PromptStateTransplant.AssertResolvable("Repair-DbaInstanceName");
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3082State"))
            {
                _state = sentinel["__w3082State"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, AutoFix.ToBool(), Force.ToBool(),
            EnableException.ToBool(), _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin line + ENTIRE process body VERBATIM per record inside a dot-sourced
    // block (four mid-loop early returns). Substitutions only: explicit -FunctionName
    // Repair-DbaInstanceName on Stop-Function/Write-Message (W1-090). $Pscmdlet stays
    // UNSUBSTITUTED (inner cmdlet serves the gates for the Force/ConfirmPreference
    // override). The `# ^ That's embarrassing` comment, the `$Error -like '*mirror*'`
    // bag-read quirk, the interactive PromptForChoice paths and the interpolated
    // sp_dropserver/sp_addserver T-SQL ride as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AutoFix, $Force, $EnableException, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, $AutoFix, $Force, $EnableException, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($Force) { $ConfirmPreference = 'none' }

    # cross-record restore: leaked fn-scope locals + the ShouldProcess Yes/No-to-All
    # engine state (lastShouldProcessContinueStatus - same field name both editions).
    # C1 transplant condition: a missing field THROWS (the C# BeginProcessing assert
    # fires first; this is the in-script belt so the transplant can never silently rot).
    $__spField = $Pscmdlet.CommandRuntime.GetType().GetField("lastShouldProcessContinueStatus", [System.Reflection.BindingFlags]"NonPublic,Instance")
    if ($null -eq $__spField) {
        throw "Repair-DbaInstanceName: prompt-state transplant field lastShouldProcessContinueStatus not resolvable on this engine (C1 assert)."
    }
    if ($null -ne $__state) {
        $renamed = $__state.renamed
        $needsrestart = $__state.needsrestart
        $allsqlservices = $__state.allsqlservices
        if ($null -ne $__state.shouldProcessContinueStatus) {
            $__spField.SetValue($Pscmdlet.CommandRuntime, [Enum]::Parse($__spField.FieldType, $__state.shouldProcessContinueStatus))
        }
    }

    . {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Repair-DbaInstanceName
            }

            if ($server.isClustered) {
                Write-Message -Level Warning -Message "$instance is a cluster. Microsoft does not support renaming clusters." -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
                continue
            }


            # Check to see if we can easily proceed

            $nametest = Test-DbaInstanceName -SqlInstance $server
            $oldServerName = $nametest.ServerName
            $newServerName = $nametest.NewServerName

            if ($nametest.RenameRequired -eq $false) {
                Stop-Function -Continue -Message "Good news! $oldServerName's @@SERVERNAME does not need to be changed. If you'd like to rename it, first rename the Windows server." -FunctionName Repair-DbaInstanceName
            }

            if (-not $nametest.Updatable) {
                Write-Message -Level Output -Message "Test-DbaInstanceName reports that the rename cannot proceed with a rename in this $instance's current state." -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"

                foreach ($nametesterror in $nametest.Blockers) {
                    if ($nametesterror -like '*replication*') {

                        if (-not $AutoFix) {
                            Stop-Function -Message "Cannot proceed because some databases are involved in replication. You can run exec sp_dropdistributor @no_checks = 1 but that may be pretty dangerous. Alternatively, you can run -AutoFix to automatically fix this issue. AutoFix will also break all database mirrors." -FunctionName Repair-DbaInstanceName
                            return
                        } else {
                            if ($Pscmdlet.ShouldProcess("console", "Prompt will appear for confirmation to break replication.")) {
                                $title = "You have chosen to AutoFix the blocker: replication."
                                $message = "We can run sp_dropdistributor which will pretty much destroy replication on this server. Do you wish to continue? (Y/N)"
                                $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                                $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                                $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                                $result = $host.ui.PromptForChoice($title, $message, $options, 1)

                                if ($result -eq 1) {
                                    Stop-Function -Message "Failure" -Target $server -Continue -FunctionName Repair-DbaInstanceName
                                } else {
                                    Write-Message -Level Output -Message "`nPerforming sp_dropdistributor @no_checks = 1." -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
                                    $sql = "EXEC dbo.sp_dropdistributor @no_checks = 1"
                                    Write-Message -Level Debug -Message $sql -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
                                    try {
                                        $null = $server.Query($sql)
                                    } catch {
                                        Stop-Function -Message "Failure" -Target $server -ErrorRecord $_ -Continue -FunctionName Repair-DbaInstanceName
                                    }
                                }
                            }
                        }
                    } elseif ($Error -like '*mirror*') {
                        if ($AutoFix -eq $false) {
                            Stop-Function -Message "Cannot proceed because some databases are being mirrored. Stop mirroring to proceed. Alternatively, you can run -AutoFix to automatically fix this issue. AutoFix will also stop replication." -Continue -FunctionName Repair-DbaInstanceName
                        } else {
                            if ($Pscmdlet.ShouldProcess("console", "Prompt will appear for confirmation to break replication.")) {
                                $title = "You have chosen to AutoFix the blocker: mirroring."
                                $message = "We can run sp_dropdistributor which will pretty much destroy replication on this server. Do you wish to continue? (Y/N)"
                                $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Will continue"
                                $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "Will exit"
                                $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
                                $result = $host.ui.PromptForChoice($title, $message, $options, 1)

                                if ($result -eq 1) {
                                    Write-Message -Level Output -Message "Okay, moving on." -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
                                } else {
                                    Write-Message -Level Verbose -Message "Removing Mirroring" -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"

                                    foreach ($database in $server.Databases) {
                                        if ($database.IsMirroringEnabled) {
                                            $dbName = $database.name

                                            try {
                                                Write-Message -Level Verbose -Message "Breaking mirror for $dbName." -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
                                                $database.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                                                $database.Alter()
                                                $database.Refresh()
                                            } catch {
                                                Stop-Function -Message "Failure" -Target $server -ErrorRecord $_ -FunctionName Repair-DbaInstanceName
                                                return
                                                #throw "Could not break mirror for $dbName. Skipping."
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            # ^ That's embarrassing

            $instanceName = $server.InstanceName

            if (-not $instanceName) {
                $instanceName = "MSSQLSERVER"
            }

            try {
                $allsqlservices = Get-Service -ComputerName $instance.ComputerName -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "SQL*$instanceName*" -and $_.Status -eq "Running" }
            } catch {
                Write-Message -Level Warning -Message "Can't contact $instance using Get-Service. This means the script will not be able to automatically restart SQL services." -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
            }

            if ($nametest.Warnings -ne 'N/A') {
                $reportingservice = Get-Service -ComputerName $instance.ComputerName -DisplayName "SQL Server Reporting Services ($instanceName)" -ErrorAction SilentlyContinue

                if ($reportingservice.Status -eq "Running") {
                    if ($Pscmdlet.ShouldProcess($server.name, "Reporting Services is running for this instance. Would you like to automatically stop this service?")) {
                        $reportingservice | Stop-Service
                        Write-Message -Level Warning -Message "You must reconfigure Reporting Services using Reporting Services Configuration Manager or PowerShell once the server has been successfully renamed." -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
                    }
                }
            }

            if ($Pscmdlet.ShouldProcess($server.name, "Performing sp_dropserver to remove the old server name, $oldServerName, then sp_addserver to add $newServerName")) {
                $sql = "EXEC dbo.sp_dropserver '$oldServerName'"
                Write-Message -Level Debug -Message $sql -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
                try {
                    $null = $server.Query($sql)
                } catch {
                    Stop-Function -Message "Failure" -Target $server -ErrorRecord $_ -FunctionName Repair-DbaInstanceName
                    return
                }

                $sql = "EXEC dbo.sp_addserver '$newServerName', LOCAL"
                Write-Message -Level Debug -Message $sql -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"

                try {
                    $null = $server.Query($sql)
                } catch {
                    Stop-Function -Message "Failure" -Target $server -ErrorRecord $_ -FunctionName Repair-DbaInstanceName
                    return
                }
                $renamed = $true
            }

            if ($null -eq $allsqlservices) {
                Write-Message -Level Warning -Message "Could not contact $($instance.ComputerName) using Get-Service. You must manually restart the SQL Server instance." -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
                $needsrestart = $true
            } else {
                if ($Pscmdlet.ShouldProcess($instance.ComputerName, "Rename complete! The SQL Service must be restarted to commit the changes. Would you like to restart the $instanceName instance now?")) {
                    try {
                        Write-Message -Level Verbose -Message "Stopping SQL Services for the $instanceName instance" -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
                        $allsqlservices | Stop-Service -Force -WarningAction SilentlyContinue # because it reports the wrong name
                        Write-Message -Level Verbose -Message "Starting SQL Services for the $instanceName instance." -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
                        $allsqlservices | Where-Object { $_.DisplayName -notlike "*reporting*" } | Start-Service -WarningAction SilentlyContinue # because it reports the wrong name
                    } catch {
                        Stop-Function -Message "Failure" -Target $server -ErrorRecord $_ -Continue -FunctionName Repair-DbaInstanceName
                    }
                }
            }

            if ($renamed -eq $true) {
                Write-Message -Level Verbose -Message "$instance successfully renamed from $oldServerName to $newServerName." -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
                Test-DbaInstanceName -SqlInstance $instance -SqlCredential $SqlCredential
            }

            if ($needsrestart -eq $true) {
                Write-Message -Level Warning -Message "SQL Service restart for $newServerName still required." -FunctionName Repair-DbaInstanceName -ModuleName "dbatools"
            }
        }
    }

    @{ __w3082State = @{ renamed = $renamed; needsrestart = $needsrestart; allsqlservices = $allsqlservices; shouldProcessContinueStatus = $(if ($null -ne $__spField) { "$($__spField.GetValue($Pscmdlet.CommandRuntime))" } else { $null }) } }
} $SqlInstance $SqlCredential $AutoFix $Force $EnableException $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
