#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Management.Infrastructure;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Windows Server Failover Cluster configuration and status information.
/// Port of public/Get-DbaWsfcCluster.ps1; surface pinned by migration/baselines/Get-DbaWsfcCluster.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaWsfcCluster")]
[OutputType(typeof(CimInstance))]
public sealed class GetDbaWsfcClusterCommand : DbaBaseCmdlet
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
            // PS: $cluster = Get-DbaCmObject -Computername $computer -Credential $Credential
            //     -Namespace root\MSCluster -ClassName MSCluster_Cluster
            // EnableException is NEVER forwarded, so a CIM failure surfaces as the inner
            // command's own warning and the computer is skipped - even when the caller
            // passed -EnableException (pinned by the characterization tests).
            List<PSObject> clusters;
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
                clusters = clusterResult.Instances;
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

            foreach (PSObject output in clusters)
            {

                // PS: $cluster | Add-Member -Force -NotePropertyName State
                //     -NotePropertyValue (Get-ResourceState $resource.State)
                // $resource is never assigned, so Get-ResourceState receives $null, matches
                // no switch branch and returns nothing: State is always a null note property.
                if (output.Properties["State"] is PSNoteProperty)
                {
                    output.Properties.Remove("State");
                }
                output.Properties.Add(new PSNoteProperty("State", null));

                OutputHelper.SetDefaultDisplayPropertySet(output,
                    "Name", "Fqdn", "State", "DrainOnShutdown", "DynamicQuorumEnabled",
                    "EnableSharedVolumes", "SharedVolumesRoot", "QuorumPath", "QuorumType",
                    "QuorumTypeValue", "RequestReplyTimeout");
                WriteObject(output);
            }
        }
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
