#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Windows Server Failover Cluster resource group status and ownership information.
/// Port of public/Get-DbaWsfcResourceGroup.ps1; surface pinned by migration/baselines/Get-DbaWsfcResourceGroup.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaWsfcResourceGroup")]
[OutputType(typeof(Microsoft.Management.Infrastructure.CimInstance))]
public sealed class GetDbaWsfcResourceGroupCommand : DbaBaseCmdlet
{
    /// <summary>The target cluster name or member node; defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Allows you to login to the cluster using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <summary>Filters results to only include resource groups with the specified names.</summary>
    [Parameter(Position = 2)]
    public string[]? Name { get; set; }

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
            // surfaces as a warning and the computer is skipped - even when the caller passed
            // -EnableException (pinned by the characterization tests).
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
                WriteMessage(MessageLevel.Warning, ex.Message, target: computer.ComputerName, exception: ex.InnerException ?? ex);
                continue;
            }

            // PS: $resources = Get-DbaCmObject -Computername $computer -Credential $Credential
            //     -Namespace root\MSCluster -ClassName MSCluster_ResourceGroup
            // EnableException is NEVER forwarded, so a CIM failure surfaces as the inner
            // command's own warning and the computer is skipped.
            List<PSObject> resources;
            try
            {
                CimService.CmObjectRequest resourceRequest = new()
                {
                    ComputerName = computer.ComputerName,
                    Credential = Credential,
                    ClassName = "MSCluster_ResourceGroup",
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
                WriteMessage(MessageLevel.Warning, ex.Message, target: computer.ComputerName, exception: ex.InnerException ?? ex);
                continue;
            }

            foreach (PSObject resource in resources)
            {
                // PS: if ($Name) { $resources = $resources | Where-Object Name -in $Name }
                // Filter by name when -Name is provided; case-insensitive (Where-Object -in uses OrdinalIgnoreCase).
                // FilterHelper.IsActive replicates PS array truthiness: a single empty/null element
                // (e.g. -Name "") is falsy and must NOT filter (cross-model review 2026-07-07 finding 12).
                if (Name is not null && FilterHelper.IsActive(Name))
                {
                    string? resourceName = resource.Properties["Name"]?.Value?.ToString();
                    bool match = false;
                    foreach (string n in Name)
                    {
                        if (string.Equals(resourceName, n, StringComparison.OrdinalIgnoreCase))
                        {
                            match = true;
                            break;
                        }
                    }
                    if (!match)
                    {
                        continue;
                    }
                }

                // PS: $resource | Add-Member -Force -NotePropertyName State
                //     -NotePropertyValue (Get-ResourceGroupState $resource.State)
                // Reads the native CIM uint16 State property and shadows it with a human-readable
                // string NoteProperty (e.g. 0 -> "Online"). The characterization test pins that
                // State is a NoteProperty of TypeNameOfValue "System.String".
                object? rawStateObj = resource.Properties["State"]?.Value;
                if (resource.Properties["State"] is PSNoteProperty)
                {
                    resource.Properties.Remove("State");
                }
                resource.Properties.Add(new PSNoteProperty("State", GetResourceGroupState(rawStateObj)));

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

                // PS: $resource | Select-DefaultView -Property ClusterName, ClusterFqdn, Name, State, PersistentState, OwnerNode
                OutputHelper.SetDefaultDisplayPropertySet(resource,
                    "ClusterName", "ClusterFqdn", "Name", "State", "PersistentState", "OwnerNode");
                WriteObject(resource);
            }
        }
    }

    /// <summary>Converts MSCluster_ResourceGroup.State integer to a human-readable string.</summary>
    /// <remarks>
    /// Faithfully ports the inline Get-ResourceGroupState from Get-DbaWsfcResourceGroup.ps1:
    /// its switch HAS a default branch returning the ORIGINAL value (preserving the input
    /// type, e.g. a uint16 7 stays uint16), and switch($null) runs no branch at all so null
    /// yields null (cross-model review 2026-07-07 finding 13, semantics proven empirically).
    /// </remarks>
    private static object? GetResourceGroupState(object? rawState)
    {
        if (rawState is null)
        {
            return null;
        }

        int state;
        try
        {
            state = Convert.ToInt32(rawState, CultureInfo.InvariantCulture);
        }
        catch
        {
            return rawState;
        }

        return state switch
        {
            -1 => "Unknown",
            0  => "Online",
            1  => "Offline",
            2  => "Failed",
            _  => rawState
        };
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
