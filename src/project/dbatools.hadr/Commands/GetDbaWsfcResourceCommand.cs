#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Management.Infrastructure;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves detailed information about cluster resources in a Windows Server Failover Cluster.
/// Port of public/Get-DbaWsfcResource.ps1; surface pinned by migration/baselines/Get-DbaWsfcResource.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaWsfcResource")]
[OutputType(typeof(CimInstance))]
public sealed class GetDbaWsfcResourceCommand : DbaBaseCmdlet
{
    /// <summary>The target cluster name or member node; defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Allows you to login to the cluster using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // PS: [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME - a machine without
        // the variable yields $null and the foreach body never runs.
        if (ComputerName is null)
        {
            return;
        }

        foreach (DbaInstanceParameter computer in ComputerName)
        {
            // PS: $cluster = Get-DbaWsfcCluster -ComputerName $computer -Credential $Credential
            // EnableException is NEVER forwarded to the inner cluster lookup, so a CIM failure
            // surfaces as a warning - even when the caller passed -EnableException (pinned by the
            // characterization tests) - and execution continues with null cluster metadata.
            string? clusterName = null;
            string? clusterFqdn = null;
            try
            {
                CimService.CmObjectRequest clusterRequest = new()
                {
                    ComputerName = computer.ComputerName,
                    Credential = Credential,
                    ClassName = "MSCluster_Cluster",
                    Namespace = @"root\MSCluster"
                };
                CimService.CmObjectResult clusterResult = CimService.GetCmObject(this, clusterRequest);
                foreach (ErrorRecord passthrough in clusterResult.PassthroughErrors)
                {
                    WriteError(NestedCommand.PreserveErrorIdentity(passthrough));
                }
                if (clusterResult.Instances.Count > 0)
                {
                    PSObject clusterObj = clusterResult.Instances[0];
                    clusterName = clusterObj.Properties["Name"]?.Value?.ToString();
                    clusterFqdn = clusterObj.Properties["Fqdn"]?.Value?.ToString();
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                // PS: the nested Get-DbaWsfcCluster lookup runs WITHOUT -EnableException, so a
                // failure warns (never errors, even under the caller's -EnableException) and
                // execution FALLS THROUGH with null cluster metadata - it does NOT skip the
                // resource query.
                NestedCommand.WarnUnforwarded(this, ex.Message, computer.ComputerName, ex.InnerException ?? ex);
            }

            // PS: $resources = Get-DbaCmObject -Computername $computer -Credential $Credential
            //     -Namespace root\MSCluster -ClassName MSCluster_Resource
            // EnableException is NEVER forwarded, so a CIM failure surfaces as the inner
            // command's own warning and the computer is skipped.
            List<PSObject> resources;
            try
            {
                CimService.CmObjectRequest resourceRequest = new()
                {
                    ComputerName = computer.ComputerName,
                    Credential = Credential,
                    ClassName = "MSCluster_Resource",
                    Namespace = @"root\MSCluster"
                };
                CimService.CmObjectResult resourceResult = CimService.GetCmObject(this, resourceRequest);
                foreach (ErrorRecord passthrough in resourceResult.PassthroughErrors)
                {
                    WriteError(NestedCommand.PreserveErrorIdentity(passthrough));
                }
                resources = resourceResult.Instances;
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                // PS: the Get-DbaCmObject MSCluster_Resource lookup runs WITHOUT -EnableException -
                // warn only, never an error even under the caller's -EnableException; $resources is
                // empty so the loop is a no-op for this computer.
                NestedCommand.WarnUnforwarded(this, ex.Message, computer.ComputerName, ex.InnerException ?? ex);
                continue;
            }

            foreach (PSObject resource in resources)
            {
                // PS: $resource | Add-Member -Force -NotePropertyName State
                //     -NotePropertyValue (Get-ResourceState $resource.State)
                // Reads the native CIM uint16 State property and shadows it with a human-readable
                // string NoteProperty (e.g. 2 → "Online"). The characterization test pins that
                // State is a NoteProperty of TypeNameOfValue "System.String".
                object? rawStateObj = resource.Properties["State"]?.Value;
                if (resource.Properties["State"] is PSNoteProperty)
                {
                    resource.Properties.Remove("State");
                }
                resource.Properties.Add(new PSNoteProperty("State", GetResourceState(rawStateObj)));

                // PS: $resource | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
                if (resource.Properties["ClusterName"] is PSNoteProperty)
                {
                    resource.Properties.Remove("ClusterName");
                }
                resource.Properties.Add(new PSNoteProperty("ClusterName", clusterName));

                // PS: $resource | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn
                if (resource.Properties["ClusterFqdn"] is PSNoteProperty)
                {
                    resource.Properties.Remove("ClusterFqdn");
                }
                resource.Properties.Add(new PSNoteProperty("ClusterFqdn", clusterFqdn));

                // PS: $resource | Select-DefaultView -Property ClusterName, ClusterFqdn, Name, State,
                //     Type, OwnerGroup, OwnerNode, PendingTimeout, PersistentState, QuorumCapable,
                //     RequiredDependencyClasses, RequiredDependencyTypes, RestartAction, RestartDelay,
                //     RestartPeriod, RestartThreshold, RetryPeriodOnFailure, SeparateMonitor
                OutputHelper.SetDefaultDisplayPropertySet(resource,
                    "ClusterName", "ClusterFqdn", "Name", "State", "Type", "OwnerGroup", "OwnerNode",
                    "PendingTimeout", "PersistentState", "QuorumCapable",
                    "RequiredDependencyClasses", "RequiredDependencyTypes",
                    "RestartAction", "RestartDelay", "RestartPeriod", "RestartThreshold",
                    "RetryPeriodOnFailure", "SeparateMonitor");
                WriteObject(resource);
            }
        }
    }

    private static readonly (int Value, string Name)[] ResourceStateLabels =
    {
        (-1, "Unknown"),
        (0, "Inherited"),
        (1, "Initializing"),
        (2, "Online"),
        (3, "Offline"),
        (4, "Failed"),
        (128, "Pending"),
        (129, "Online Pending"),
        (130, "Offline Pending")
    };

    /// <summary>Converts MSCluster_Resource.State integer to a human-readable string.</summary>
    /// <remarks>
    /// Faithfully ports private/functions/Get-ResourceState.ps1: the PS switch has NO default
    /// branch, so null input and any unmatched value yield null - never "Unknown" and never
    /// the original value (cross-model review 2026-07-07 finding 11). The PS
    /// `switch ($state) { 2 { ... } }` compares each integer label against the raw value with PS
    /// -eq scalar semantics - NOT Convert.ToInt32. That distinction is observable: "2", 2.0 and
    /// [decimal]2 MATCH (the label coerces to the value's type and compares equal), but "02", 2.4
    /// and any [bool] do NOT (no branch, no default -> null). Convert.ToInt32 over-coerced all of
    /// those into false matches (cross-model return-sweep 2026-07-20). LanguagePrimitives.Equals
    /// reproduces the switch's per-label coercion; the [bool] guard reproduces the switch NOT
    /// numeric-coercing booleans. Verified 14/14 against a live PS switch.
    /// </remarks>
    private static string? GetResourceState(object? rawState)
    {
        if (rawState is null)
        {
            return null;
        }

        // PS `switch` does NOT numeric-coerce a [bool] to match an integer label (unlike -eq's
        // [bool] cast), so $true/$false fall through to null.
        if (rawState is bool)
        {
            return null;
        }

        // PS `switch ($state)` treats a [char] like its 1-char string (probed: [char]'0'..'4'
        // match cases 0..4 - e.g. [char]'2' -> "Online" - via the char's string form, NOT its
        // code point). LanguagePrimitives.Equals(char, int) would instead cast the int label to a
        // NUL char and miss, so normalize a char to its string form to match PS. (Unreachable for
        // the live WMI uint State, but faithful - cross-model return-sweep r2.)
        if (rawState is char rawStateChar)
        {
            rawState = rawStateChar.ToString();
        }

        foreach ((int value, string name) in ResourceStateLabels)
        {
            if (LanguagePrimitives.Equals(rawState, value, ignoreCase: true, CultureInfo.InvariantCulture))
            {
                return name;
            }
        }

        return null;
    }

    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine))
        {
            return null;
        }
        return new[] { new DbaInstanceParameter(machine) };
    }
}
