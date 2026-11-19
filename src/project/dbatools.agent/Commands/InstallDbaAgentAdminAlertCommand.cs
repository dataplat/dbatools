#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a standard set of SQL Server Agent administrative alerts, plus the operator and alert
/// category they notify, on the target instances.
/// </summary>
/// <remarks>
/// The whole begin/process workflow runs the original dbatools PowerShell body inside the dbatools
/// module scope rather than being reimplemented in C#, so the engine decides the observable details:
/// the alert set, the SMO existence checks, the operator and category creation, the ShouldProcess
/// prompts, and the output decoration.
///
/// The retired function computes its severity/error alert table and its default display set once in a
/// begin block. That table depends only on bound parameters, not on pipeline data, and the only
/// mutation it undergoes is removing the -ExcludeSeverity / -ExcludeMessageId entries, which are the
/// same bound values for every record; rebuilding it at the top of each record's hop therefore
/// produces the same table the begin block would have, so the begin logic is folded into the process
/// hop rather than carried between two hops.
///
/// Output streams as it is produced. The body creates alerts and emits the resulting object for each
/// before a later one may fail under -EnableException; buffering those and losing them to a later
/// terminating failure would hide the record of alerts that were actually created.
///
/// This cmdlet supplies the real ShouldProcess runtime to the hop. Surface pinned by
/// migration/baselines/Install-DbaAgentAdminAlert.json.
/// </remarks>
[Cmdlet(VerbsLifecycle.Install, "DbaAgentAdminAlert", SupportsShouldProcess = true,
    ConfirmImpact = ConfirmImpact.Low)]
public sealed class InstallDbaAgentAdminAlertCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The alert category to assign, created if it does not exist.</summary>
    [Parameter(Position = 2)]
    public string? Category { get; set; }

    /// <summary>Restrict the alerts to a specific database.</summary>
    [Parameter(Position = 3)]
    public string? Database { get; set; }

    /// <summary>The operator to notify, looked up or created.</summary>
    [Parameter(Position = 4)]
    public string? Operator { get; set; }

    /// <summary>The email address for a newly created operator.</summary>
    [Parameter(Position = 5)]
    public string? OperatorEmail { get; set; }

    /// <summary>Seconds to wait between responses for each alert.</summary>
    [Parameter(Position = 6)]
    public int DelayBetweenResponses { get; set; }

    /// <summary>Create the alerts in a disabled state.</summary>
    [Parameter]
    public SwitchParameter Disabled { get; set; }

    /// <summary>Only raise alerts whose error text contains this keyword.</summary>
    [Parameter(Position = 7)]
    public string? EventDescriptionKeyword { get; set; }

    /// <summary>Only raise alerts from this event source.</summary>
    [Parameter(Position = 8)]
    public string? EventSource { get; set; }

    /// <summary>The Agent job to run in response to each alert.</summary>
    [Parameter(Position = 9)]
    public string JobId { get; set; } = "00000000-0000-0000-0000-000000000000";

    /// <summary>Severity levels to exclude from the created alerts.</summary>
    [Parameter(Position = 10)]
    public int[]? ExcludeSeverity { get; set; }

    /// <summary>Message ids to exclude from the created alerts.</summary>
    [Parameter(Position = 11)]
    public int[]? ExcludeMessageId { get; set; }

    /// <summary>The notification message sent with each alert.</summary>
    [Parameter(Position = 12)]
    public string? NotificationMessage { get; set; }

    /// <summary>How the operator is notified.</summary>
    [Parameter(Position = 13)]
    [PsStringCast]
    [ValidateSet("None", "NotifyEmail", "Pager", "NetSend", "NotifyAll")]
    public string NotifyMethod { get; set; } = "NotifyAll";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The function reassigns $Operator (to the resolved operator name) when -Operator is unbound, and
    // reads it at the top of the NEXT pipeline record; the function scope spans the pipeline, so that
    // value leaks forward. A per-record hop resets it, so the reassigned value is carried across records
    // to reproduce that behavior. Starts as the bound value (null when unbound).
    private object? _operatorState;
    private bool _operatorInitialized;

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (!_operatorInitialized)
        {
            _operatorState = Operator;
            _operatorInitialized = true;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__InstallDbaAgentAdminAlertProcessComplete"]?.Value))
            {
                _operatorState = item.Properties["Operator"]?.Value;
            }
            else
            {
                WriteObject(item);
            }
        }, BodyScript,
            SqlInstance, SqlCredential, Category, Database, _operatorState, OperatorEmail,
            DelayBetweenResponses, Disabled.ToBool(), EventDescriptionKeyword, EventSource,
            JobId, ExcludeSeverity, ExcludeMessageId, NotificationMessage, NotifyMethod,
            EnableException.ToBool(), BoundRaw("JobId"), BoundRaw("Category"),
            BoundRaw("DelayBetweenResponses"), BoundRaw("Operator"), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private object? BoundRaw(string name)
    {
        if (MyInvocation.BoundParameters.TryGetValue(name, out object? value))
        {
            return value;
        }
        return null;
    }

    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Category, $Database, $Operator, $OperatorEmail, $DelayBetweenResponses, $Disabled, $EventDescriptionKeyword, $EventSource, $JobId, $ExcludeSeverity, $ExcludeMessageId, $NotificationMessage, $NotifyMethod, $EnableException, $__boundJobId, $__boundCategory, $__boundDelayBetweenResponses, $__boundOperator, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Category, [string]$Database, [string]$Operator, [string]$OperatorEmail, [int]$DelayBetweenResponses, $Disabled, [string]$EventDescriptionKeyword, [string]$EventSource, [string]$JobId, [int[]]$ExcludeSeverity, [int[]]$ExcludeMessageId, [string]$NotificationMessage, [string]$NotifyMethod, $EnableException, $__boundJobId, $__boundCategory, $__boundDelayBetweenResponses, $__boundOperator, $__realCmdlet)

    $namehash = @{
        17  = 'Severity 017 - Insufficient Resources'
        18  = 'Severity 018 - Nonfatal Internal Error'
        19  = 'Severity 019 - SQL Server Error in Resource'
        20  = 'Severity 020 - SQL Server Fatal Error in Current Process'
        21  = 'Severity 021 - SQL Server Fatal Error in Database Process'
        22  = 'Severity 022 - Table Integrity Suspect'
        23  = 'Severity 023 - Database Integrity Suspect'
        24  = 'Severity 024 - Hardware Error'
        25  = 'Severity 025 - Fatal System Error'
        823 = 'Error Number 823 - Read/Write Error'
        824 = 'Error Number 824 - Read/Write Error'
        825 = 'Error Number 825 - Read/Write Error'
    }

    $defaults = "ComputerName", "SqlInstance", "InstanceName", "Name", "Severity", "MessageId"

    if ($__boundJobId) {
        $defaults += "JobName"
    }

    if ($__boundCategory) {
        $defaults += "CategoryName"
    }

    if ($__boundDelayBetweenResponses) {
        $defaults += "DelayBetweenResponses"
    }
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Install-DbaAgentAdminAlert
        }

        if ($Operator) {
            try {
                $newop = Get-DbaAgentOperator -SqlInstance $server -Operator $Operator
                if (-not $newop -and $OperatorEmail) {
                    if ($__realCmdlet.ShouldProcess($instance, "Creating operator $Operator with email $OperatorEmail")) {
                        Write-Message -Level Verbose -Message "Creating operator $Operator with email $OperatorEmail on $instance" -FunctionName Install-DbaAgentAdminAlert -ModuleName "dbatools"
                        $parms = @{
                            SqlInstance = $server
                            Operator    = $Operator
                            Email       = $OperatorEmail
                        }
                        $newop = New-DbaAgentOperator @parms
                        $null = $server.JobServer.Operators.Refresh()
                        $null = $server.JobServer.Refresh()

                        if (-not $newop) {
                            $parms = @{
                                Message  = "Failed to create operator $Operator with email $OperatorEmail on $instance"
                                Target   = $instance
                                Continue = $true
                            }
                            Stop-Function @parms -FunctionName Install-DbaAgentAdminAlert
                        }
                    }
                }
            } catch {
                Stop-Function -Message "Failure" -Category OperatorError -ErrorRecord $PSItem -Target $instance -Continue -FunctionName Install-DbaAgentAdminAlert
            }
        }

        if ($Category) {
            try {
                $newcat = Get-DbaAgentAlertCategory -SqlInstance $server -Category $Category
                if (-not $newcat) {
                    if ($__realCmdlet.ShouldProcess($instance, "Creating alert category $Category")) {
                        Write-Message -Level Verbose -Message "Creating alert category $Category on $instance" -FunctionName Install-DbaAgentAdminAlert -ModuleName "dbatools"
                        $parms = @{
                            SqlInstance = $server
                            Category    = $Category
                        }
                        $newcat = New-DbaAgentAlertCategory @parms

                        if (-not $newcat) {
                            $parms = @{
                                Message  = "Failed to create category $Category on $instance"
                                Target   = $instance
                                Continue = $true
                            }
                            Stop-Function @parms -FunctionName Install-DbaAgentAdminAlert
                        }
                    }
                }
            } catch {
                Stop-Function -Message "Failure" -Category OperatorError -ErrorRecord $PSItem -Target $instance -Continue -FunctionName Install-DbaAgentAdminAlert
            }
        }

        if (-not $__boundOperator) {
            if ($__realCmdlet.ShouldProcess($instance, "Checking for operator $Operator")) {
                $newop = Get-DbaAgentOperator -SqlInstance $server
                if ($newop.Count -gt 1) {
                    Stop-Function -Message "More than one operator found on $instance and operator not specified" -Target $instance -Continue -FunctionName Install-DbaAgentAdminAlert
                }

                if ($newop.Count -eq 0) {
                    Stop-Function -Message "No operator found on $instance and operator not specified. You can create a new operator using the Operator and OperatorEmail parameters." -Target $instance -Continue -FunctionName Install-DbaAgentAdminAlert
                }
            }
            $Operator = $newop.Name
        }

        $parms = @{
            SqlInstance  = $server
            Alert        = $name
            Disabled     = $Disabled
            NotifyMethod = $NotifyMethod
        }

        if ($DelayBetweenResponses -gt 0) {
            $null = $parms.Add("DelayBetweenResponses", $DelayBetweenResponses)
        }

        if ($Database) {
            $null = $parms.Add("Database", $Database)
        }

        if ($EventDescriptionKeyword) {
            $null = $parms.Add("EventDescriptionKeyword", $EventDescriptionKeyword)
        }

        if ($EventSource) {
            $null = $parms.Add("EventSource", $EventSource)
        }

        if ($JobId) {
            $null = $parms.Add("JobId", $JobId)
        }

        if ($NotificationMessage) {
            $null = $parms.Add("NotificationMessage", $NotificationMessage)
        }

        if ($Operator) {
            $null = $parms.Add("Operator", $Operator)
        }

        if ($Category) {
            $null = $parms.Add("Category", $Category)
        }

        if ($ExcludeSeverity) {
            foreach ($number in $ExcludeSeverity) {
                $null = $namehash.Remove($number)
            }
        }

        if ($ExcludeMessageId) {
            foreach ($number in $ExcludeMessageId) {
                $null = $namehash.Remove($number)
            }
        }

        foreach ($item in $namehash.Keys) {
            $name = $namehash[$item]
            $parms.Alert = $name
            $parms.Severity = 0
            $parms.MessageId = 0

            if ($item -lt 823) {
                $parms.Severity = $item
            } else {
                $parms.MessageId = $item
            }

            if ($name -in $server.JobServer.Alerts.Name) {
                Stop-Function -Message "Alert '$name' already exists on $instance" -Target $instance -Continue -FunctionName Install-DbaAgentAdminAlert
            } else {
                if ($__realCmdlet.ShouldProcess($instance, "Adding the alert $name")) {
                    try {
                        # Supply either a non-zero message ID, non-zero severity, non-null performance condition, or non-null WMI namespace and query.
                        $null = New-DbaAgentAlert @parms -EnableException
                    } catch {
                        Stop-Function -Message "Something went wrong creating the alert $name on $instance" -Target $name -Continue -ErrorRecord $_ -FunctionName Install-DbaAgentAdminAlert
                    }
                }
            }
            Get-DbaAgentAlert -SqlInstance $server -Alert $name | Select-DefaultView -Property $defaults
        }
    }

    [pscustomobject]@{
        __InstallDbaAgentAdminAlertProcessComplete = $true
        Operator = $Operator
    }
} $SqlInstance $SqlCredential $Category $Database $Operator $OperatorEmail $DelayBetweenResponses $Disabled $EventDescriptionKeyword $EventSource $JobId $ExcludeSeverity $ExcludeMessageId $NotificationMessage $NotifyMethod $EnableException $__boundJobId $__boundCategory $__boundDelayBetweenResponses $__boundOperator $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
