#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a SQL Server Agent alert on the target instances.
/// </summary>
/// <remarks>
/// The SMO alert construction, the property assignment loop, the operator notifications, and the
/// output run the original dbatools PowerShell body inside the dbatools module scope rather than
/// being reimplemented in C#, so the engine decides the observable details.
///
/// Output streams as it is produced. A single record can create alerts across several instances,
/// and each created alert is emitted before a later one may fail under -EnableException; buffering
/// them and losing them to a later terminating failure would hide alerts that were actually created.
///
/// This cmdlet supplies the real ShouldProcess runtime to the hop. Surface pinned by
/// migration/baselines/New-DbaAgentAlert.json.
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaAgentAlert", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaAgentAlertCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name of the alert to create.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [ValidateNotNullOrEmpty]
    [PsStringCast]
    public string Alert { get; set; } = null!;

    /// <summary>The alert category name.</summary>
    [Parameter(Position = 3)]
    public string? Category { get; set; }

    /// <summary>Restrict the alert to a specific database.</summary>
    [Parameter(Position = 4)]
    public string? Database { get; set; }

    /// <summary>Operators to notify when the alert fires.</summary>
    [Parameter(Position = 5)]
    public string[]? Operator { get; set; }

    /// <summary>Seconds to wait between responses for the alert.</summary>
    [Parameter(Position = 6)]
    public int DelayBetweenResponses { get; set; } = 60;

    /// <summary>Create the alert in a disabled state.</summary>
    [Parameter]
    public SwitchParameter Disabled { get; set; }

    /// <summary>Only raise the alert when the error text contains this keyword.</summary>
    [Parameter(Position = 7)]
    public string? EventDescriptionKeyword { get; set; }

    /// <summary>Only raise the alert from this event source.</summary>
    [Parameter(Position = 8)]
    public string? EventSource { get; set; }

    /// <summary>The Agent job to run in response to the alert.</summary>
    [Parameter(Position = 9)]
    public string JobId { get; set; } = "00000000-0000-0000-0000-000000000000";

    /// <summary>The severity level that raises the alert.</summary>
    [Parameter(Position = 10)]
    public int Severity { get; set; }

    /// <summary>The message id that raises the alert.</summary>
    [Parameter(Position = 11)]
    public int MessageId { get; set; }

    /// <summary>The notification message sent with the alert.</summary>
    [Parameter(Position = 12)]
    public string? NotificationMessage { get; set; }

    /// <summary>A performance condition that raises the alert.</summary>
    [Parameter(Position = 13)]
    public string? PerformanceCondition { get; set; }

    /// <summary>The WMI namespace for a WMI event alert.</summary>
    [Parameter(Position = 14)]
    public string? WmiEventNamespace { get; set; }

    /// <summary>The WMI query for a WMI event alert.</summary>
    [Parameter(Position = 15)]
    public string? WmiEventQuery { get; set; }

    /// <summary>How the operators are notified.</summary>
    [Parameter(Position = 16)]
    [PsStringCast]
    [ValidateSet("None", "NotifyEmail", "Pager", "NetSend", "NotifyAll")]
    public string NotifyMethod { get; set; } = "NotifyAll";

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, BodyScript,
            SqlInstance, SqlCredential, Alert, Category, Database, Operator,
            DelayBetweenResponses, Disabled.ToBool(), EventDescriptionKeyword, EventSource,
            JobId, Severity, MessageId, NotificationMessage, PerformanceCondition,
            WmiEventNamespace, WmiEventQuery, NotifyMethod, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Alert, $Category, $Database, $Operator, $DelayBetweenResponses, $Disabled, $EventDescriptionKeyword, $EventSource, $JobId, $Severity, $MessageId, $NotificationMessage, $PerformanceCondition, $WmiEventNamespace, $WmiEventQuery, $NotifyMethod, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string]$Alert, [string]$Category, [string]$Database, [string[]]$Operator, [int]$DelayBetweenResponses, $Disabled, [string]$EventDescriptionKeyword, [string]$EventSource, [string]$JobId, [int]$Severity, [int]$MessageId, [string]$NotificationMessage, [string]$PerformanceCondition, [string]$WmiEventNamespace, [string]$WmiEventQuery, [string]$NotifyMethod, $EnableException, $__realCmdlet)

    if ($NotifyMethod) {
        $null = Set-Variable -Name IncludeEventDescription -Value $NotifyMethod
    }

    if ($Category) {
        $null = Set-Variable -Name CategoryName -Value $Category
    }

    if ($Database) {
        $null = Set-Variable -Name DatabaseName -Value $Database
    }

    if ($MessageId -gt 0 -and -not $Severity) {
        $Severity = 0
    }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaAgentAlert
        }

        foreach ($name in $Alert) {
            if ($name -in $server.JobServer.Alerts.Name) {
                Stop-Function -Message "Alert '$name' already exists on $instance" -Target $instance -Continue -FunctionName New-DbaAgentAlert
            } else {
                if ($__realCmdlet.ShouldProcess($instance, "Adding the alert $name")) {
                    try {
                        # Supply either a non-zero message ID, non-zero severity, non-null performance condition, or non-null WMI namespace and query.
                        try {
                            $newalert = New-Object Microsoft.SqlServer.Management.Smo.Agent.Alert($server.JobServer, $name)
                        } catch {
                            if ($_.Exception.Message -match "newParent") {
                                Stop-Function -Message "Cannot create agent alert through a contained availability group listener. SQL Server Agent objects are instance-level and must be managed on the instance directly. Please connect to the primary replica instead of the listener. Use Get-DbaAvailabilityGroup to find the current primary replica." -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaAgentAlert
                                return
                            } else {
                                throw
                            }
                        }
                        $list = "CategoryName", "DatabaseName", "DelayBetweenResponses", "EventDescriptionKeyword", "EventSource", "JobID", "MessageID", "NotificationMessage", "PerformanceCondition", "WmiEventNamespace", "WmiEventQuery", "IncludeEventDescription", "IsEnabled", "Severity"

                        foreach ($item in $list) {
                            $value = (Get-Variable -Name $item -ErrorAction Ignore).Value

                            if ($value) {
                                $newalert.$item = $value
                            }
                        }

                        $newalert.Create()

                        if ($Operator -and $NotifyMethod) {
                            foreach ($op in $Operator) {
                                try {
                                    Write-Message -Level Verbose -Message "Adding notification of type $NotifyMethod for $op to $instance" -FunctionName New-DbaAgentAlert -ModuleName "dbatools"
                                    $newalert.AddNotification($op, [Microsoft.SqlServer.Management.Smo.Agent.NotifyMethods]::$NotifyMethod)
                                    $newalert.Alter()
                                } catch {
                                    Stop-Function -Message "Error adding notification of type $NotifyMethod for $op to $instance" -Target $name -Continue -ErrorRecord $_ -FunctionName New-DbaAgentAlert
                                }
                            }
                        }
                        $null = $server.JobServer.Refresh()
                    } catch {
                        Stop-Function -Message "Something went wrong creating the alert $name on $instance" -Target $name -Continue -ErrorRecord $PSItem -FunctionName New-DbaAgentAlert
                    }
                }
            }
            Get-DbaAgentAlert -SqlInstance $server -Alert $name
        }
    }
} $SqlInstance $SqlCredential $Alert $Category $Database $Operator $DelayBetweenResponses $Disabled $EventDescriptionKeyword $EventSource $JobId $Severity $MessageId $NotificationMessage $PerformanceCondition $WmiEventNamespace $WmiEventQuery $NotifyMethod $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
