#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Windows Server Failover Cluster role (resource group) status and ownership information.
/// Port of public/Get-DbaWsfcRole.ps1; surface pinned by migration/baselines/Get-DbaWsfcRole.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaWsfcRole")]
[OutputType(typeof(Microsoft.Management.Infrastructure.CimInstance))]
public sealed class GetDbaWsfcRoleCommand : DbaBaseCmdlet
{
    /// <summary>Specifies the cluster node name or cluster name to connect to. Defaults to the local computer.</summary>
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

            // PS: $role = Get-DbaCmObject -Computername $computer -Credential $Credential
            //     -Namespace root\MSCluster -ClassName MSCluster_ResourceGroup
            // EnableException is NEVER forwarded, so a CIM failure surfaces as the inner
            // command's own warning and the computer is skipped.
            List<PSObject> roles;
            try
            {
                CimService.CmObjectRequest roleRequest = new()
                {
                    ComputerName = computer.ComputerName,
                    Credential = Credential,
                    ClassName = "MSCluster_ResourceGroup",
                    Namespace = @"root\MSCluster"
                };
                CimService.CmObjectResult roleResult = CimService.GetCmObject(this, roleRequest);
                foreach (ErrorRecord passthrough in roleResult.PassthroughErrors)
                {
                    WriteError(NestedCommand.PreserveErrorIdentity(passthrough));
                }
                roles = roleResult.Instances;
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

            foreach (PSObject role in roles)
            {
                // PS: $role | Add-Member -Force -NotePropertyName State -NotePropertyValue (Get-ResourceState $resource.State)
                // BUG IN PS SOURCE: the loop variable is $role but the code references $resource.State;
                // $resource is undefined in this scope, so $resource.State is $null, and Get-ResourceState $null
                // returns nothing (empty/null). State is therefore always $null on every returned role.
                // Characterization test pins this behavior: do not "fix" without a surface-diff decision.
                if (role.Properties["State"] is PSNoteProperty)
                {
                    role.Properties.Remove("State");
                }
                role.Properties.Add(new PSNoteProperty("State", null));

                // PS: $role | Add-Member -Force -NotePropertyName ClusterName -NotePropertyValue $cluster.Name
                if (role.Properties["ClusterName"] is PSNoteProperty)
                {
                    role.Properties.Remove("ClusterName");
                }
                role.Properties.Add(new PSNoteProperty("ClusterName", clusterName));

                // PS: $role | Add-Member -Force -NotePropertyName ClusterFqdn -NotePropertyValue $cluster.Fqdn
                if (role.Properties["ClusterFqdn"] is PSNoteProperty)
                {
                    role.Properties.Remove("ClusterFqdn");
                }
                role.Properties.Add(new PSNoteProperty("ClusterFqdn", clusterFqdn));

                // PS: $role | Select-DefaultView -Property ClusterName, ClusterFqdn, Name, OwnerNode, State
                OutputHelper.SetDefaultDisplayPropertySet(role,
                    "ClusterName", "ClusterFqdn", "Name", "OwnerNode", "State");
                WriteObject(role);
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
