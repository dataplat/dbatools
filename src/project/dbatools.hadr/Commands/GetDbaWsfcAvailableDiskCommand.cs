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
/// Retrieves shared storage disks available for clustering but not yet assigned to a Windows Server Failover Cluster.
/// Port of public/Get-DbaWsfcAvailableDisk.ps1; surface pinned by migration/baselines/Get-DbaWsfcAvailableDisk.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaWsfcAvailableDisk")]
[OutputType(typeof(CimInstance))]
public sealed class GetDbaWsfcAvailableDiskCommand : DbaBaseCmdlet
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

            // PS: $disk = Get-DbaCmObject -Computername $computer -Credential $Credential
            //     -Namespace root\MSCluster -ClassName MSCluster_AvailableDisk
            // EnableException is NEVER forwarded, so a CIM failure surfaces as the inner
            // command's own warning and the computer is skipped.
            List<PSObject> disks;
            try
            {
                CimService.CmObjectRequest diskRequest = new()
                {
                    ComputerName = computer.ComputerName,
                    Credential = Credential,
                    ClassName = "MSCluster_AvailableDisk",
                    Namespace = @"root\MSCluster"
                };
                CimService.CmObjectResult diskResult = CimService.GetCmObject(this, diskRequest);
                foreach (ErrorRecord passthrough in diskResult.PassthroughErrors)
                {
                    WriteError(NestedCommand.PreserveErrorIdentity(passthrough));
                }
                disks = diskResult.Instances;
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

            foreach (PSObject disk in disks)
            {
                // PS: $disk | Add-Member -Force -NotePropertyName State -NotePropertyValue (Get-ResourceState $resource.State)
                // $resource is never assigned; Get-ResourceState receives $null and returns nothing.
                // I don't have an available disk, so I can't see how to clean this up: Passthru
                // State is always null - replicated exactly per characterization tests.
                if (disk.Properties["State"] is PSNoteProperty)
                {
                    disk.Properties.Remove("State");
                }
                disk.Properties.Add(new PSNoteProperty("State", null));

                // PS: $disk | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
                if (disk.Properties["ClusterName"] is PSNoteProperty)
                {
                    disk.Properties.Remove("ClusterName");
                }
                disk.Properties.Add(new PSNoteProperty("ClusterName", clusterName));

                // PS: $disk | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn -PassThru
                if (disk.Properties["ClusterFqdn"] is PSNoteProperty)
                {
                    disk.Properties.Remove("ClusterFqdn");
                }
                disk.Properties.Add(new PSNoteProperty("ClusterFqdn", clusterFqdn));

                WriteObject(disk);
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
