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
/// Retrieves network interface configuration from Windows Server Failover Cluster nodes.
/// Port of public/Get-DbaWsfcNetworkInterface.ps1; surface pinned by migration/baselines/Get-DbaWsfcNetworkInterface.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaWsfcNetworkInterface")]
[OutputType(typeof(CimInstance))]
public sealed class GetDbaWsfcNetworkInterfaceCommand : DbaBaseCmdlet
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

            // PS: $network = Get-DbaCmObject -Computername $computer -Credential $Credential
            //     -Namespace root\MSCluster -ClassName MSCluster_NetworkInterface
            // EnableException is NEVER forwarded, so a CIM failure surfaces as the inner
            // command's own warning and the computer is skipped.
            List<PSObject> networkInterfaces;
            try
            {
                CimService.CmObjectRequest interfaceRequest = new()
                {
                    ComputerName = computer.ComputerName,
                    Credential = Credential,
                    ClassName = "MSCluster_NetworkInterface",
                    Namespace = @"root\MSCluster"
                };
                CimService.CmObjectResult interfaceResult = CimService.GetCmObject(this, interfaceRequest);
                foreach (ErrorRecord passthrough in interfaceResult.PassthroughErrors)
                {
                    WriteError(NestedCommand.PreserveErrorIdentity(passthrough));
                }
                networkInterfaces = interfaceResult.Instances;
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

            foreach (PSObject networkInterface in networkInterfaces)
            {
                // PS: $network | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
                // PS: $network | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn
                // Inject cluster identity as NoteProperty members (not native MSCluster_NetworkInterface CIM properties).
                if (networkInterface.Properties["ClusterName"] is PSNoteProperty)
                {
                    networkInterface.Properties.Remove("ClusterName");
                }
                networkInterface.Properties.Add(new PSNoteProperty("ClusterName", clusterName));

                if (networkInterface.Properties["ClusterFqdn"] is PSNoteProperty)
                {
                    networkInterface.Properties.Remove("ClusterFqdn");
                }
                networkInterface.Properties.Add(new PSNoteProperty("ClusterFqdn", clusterFqdn));

                // PS: $network | Select-DefaultView -Property ClusterName, ClusterFqdn, Name,
                //     Network, Node, Adapter, Address, DhcpEnabled, IPv4Addresses,
                //     IPv6Addresses, IPv6Addresses
                // Note: IPv6Addresses appears twice in the PS source (copy-paste quirk); the
                // DefaultDisplayPropertySet deduplicates so the duplicate has no effect on output.
                OutputHelper.SetDefaultDisplayPropertySet(networkInterface,
                    "ClusterName", "ClusterFqdn", "Name", "Network", "Node",
                    "Adapter", "Address", "DhcpEnabled", "IPv4Addresses", "IPv6Addresses");
                WriteObject(networkInterface);
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
