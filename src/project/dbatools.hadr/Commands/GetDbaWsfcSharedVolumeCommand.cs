#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.Management.Infrastructure;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Cluster Shared Volume configuration and status from Windows Server Failover Clusters hosting SQL Server instances.
/// Port of public/Get-DbaWsfcSharedVolume.ps1; surface pinned by migration/baselines/Get-DbaWsfcSharedVolume.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaWsfcSharedVolume")]
[OutputType(typeof(CimInstance))]
public sealed class GetDbaWsfcSharedVolumeCommand : DbaBaseCmdlet
{
    /// <summary>Specifies the target Windows Server Failover Cluster to query. Defaults to the local computer.</summary>
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

            // PS: $volume = Get-DbaCmObject -Computername $computer -Credential $Credential
            //     -Namespace root\MSCluster -ClassName ClusterSharedVolume
            // EnableException is NEVER forwarded, so a CIM failure surfaces as the inner
            // command's own warning and the computer is skipped.
            List<PSObject> volumes;
            try
            {
                CimService.CmObjectRequest volumeRequest = new()
                {
                    ComputerName = computer.ComputerName,
                    Credential = Credential,
                    ClassName = "ClusterSharedVolume",
                    Namespace = @"root\MSCluster"
                };
                CimService.CmObjectResult volumeResult = CimService.GetCmObject(this, volumeRequest);
                foreach (ErrorRecord passthrough in volumeResult.PassthroughErrors)
                {
                    WriteError(NestedCommand.PreserveErrorIdentity(passthrough));
                }
                volumes = volumeResult.Instances;
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

            // I don't have a shared volume, so I can't see how to clean this up: Passthru
            foreach (PSObject volume in volumes)
            {
                // PS: $volume | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
                if (volume.Properties["ClusterName"] is PSNoteProperty)
                {
                    volume.Properties.Remove("ClusterName");
                }
                volume.Properties.Add(new PSNoteProperty("ClusterName", clusterName));

                // PS: $volume | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn
                if (volume.Properties["ClusterFqdn"] is PSNoteProperty)
                {
                    volume.Properties.Remove("ClusterFqdn");
                }
                volume.Properties.Add(new PSNoteProperty("ClusterFqdn", clusterFqdn));

                // PS: $volume | Add-Member -Force -NotePropertyName State -NotePropertyValue (Get-ResourceState $resource.State) -PassThru
                // BUG IN PS SOURCE: the loop variable is $volume but the code references $resource.State;
                // $resource is undefined in this scope, so $resource.State is $null, and Get-ResourceState $null
                // returns nothing (empty/null). State is therefore always $null on every returned volume.
                // characterization: State variable bug -- do not "fix" without a surface-diff decision.
                if (volume.Properties["State"] is PSNoteProperty)
                {
                    volume.Properties.Remove("State");
                }
                volume.Properties.Add(new PSNoteProperty("State", null));

                WriteObject(volume);
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
