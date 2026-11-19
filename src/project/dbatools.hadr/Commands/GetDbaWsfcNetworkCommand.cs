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
/// Retrieves network configuration details from Windows Server Failover Clusters for SQL Server HA troubleshooting.
/// Port of public/Get-DbaWsfcNetwork.ps1; surface pinned by migration/baselines/Get-DbaWsfcNetwork.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaWsfcNetwork")]
[OutputType(typeof(CimInstance))]
public sealed class GetDbaWsfcNetworkCommand : DbaBaseCmdlet
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
            //     -Namespace root\MSCluster -ClassName MSCluster_Network
            // EnableException is NEVER forwarded, so a CIM failure surfaces as the inner
            // command's own warning and the computer is skipped.
            List<PSObject> networks;
            try
            {
                CimService.CmObjectRequest networkRequest = new()
                {
                    ComputerName = computer.ComputerName,
                    Credential = Credential,
                    ClassName = "MSCluster_Network",
                    Namespace = @"root\MSCluster"
                };
                CimService.CmObjectResult networkResult = CimService.GetCmObject(this, networkRequest);
                foreach (ErrorRecord passthrough in networkResult.PassthroughErrors)
                {
                    WriteError(NestedCommand.PreserveErrorIdentity(passthrough));
                }
                networks = networkResult.Instances;
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

            foreach (PSObject network in networks)
            {
                // PS: $network | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
                // PS: $network | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn
                // Inject cluster identity as NoteProperty members (not native MSCluster_Network CIM properties).
                if (network.Properties["ClusterName"] is PSNoteProperty)
                {
                    network.Properties.Remove("ClusterName");
                }
                network.Properties.Add(new PSNoteProperty("ClusterName", clusterName));

                if (network.Properties["ClusterFqdn"] is PSNoteProperty)
                {
                    network.Properties.Remove("ClusterFqdn");
                }
                network.Properties.Add(new PSNoteProperty("ClusterFqdn", clusterFqdn));

                // PS: $network | Select-DefaultView -Property ClusterName, ClusterFqdn, Name,
                //     Address, AddressMask, IPv4Addresses, IPv4PrefixLengths, IPv6Addresses,
                //     IPv6PrefixLengths, QuorumType, QuorumTypeValue, RequestReplyTimeout, Role
                OutputHelper.SetDefaultDisplayPropertySet(network,
                    "ClusterName", "ClusterFqdn", "Name", "Address", "AddressMask",
                    "IPv4Addresses", "IPv4PrefixLengths", "IPv6Addresses", "IPv6PrefixLengths",
                    "QuorumType", "QuorumTypeValue", "RequestReplyTimeout", "Role");
                WriteObject(network);
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
