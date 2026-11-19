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
/// Retrieves detailed information about clustered physical disks from Windows Server Failover Clusters.
/// Port of public/Get-DbaWsfcDisk.ps1; surface pinned by migration/baselines/Get-DbaWsfcDisk.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaWsfcDisk")]
[OutputType(typeof(PSObject))]
public sealed class GetDbaWsfcDiskCommand : DbaBaseCmdlet
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
            // surfaces as a warning and execution continues with null cluster metadata.
            string? clusterName = null;
            string? clusterFqdn = null;
            try
            {
                CimService.CmObjectRequest clusterRequest = new CimService.CmObjectRequest()
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
                // PS: the inlined Get-DbaWsfcResource -> Get-DbaWsfcCluster lookup runs WITHOUT
                // -EnableException, so a failure warns (never errors, even under the caller's
                // -EnableException) and execution FALLS THROUGH with null cluster metadata - it
                // does NOT skip the resource query.
                NestedCommand.WarnUnforwarded(this, ex.Message, computer.ComputerName, ex.InnerException ?? ex);
            }

            // PS: $resources = Get-DbaWsfcResource -ComputerName $computer -Credential $Credential
            //     | Where-Object Type -eq 'Physical Disk'
            // Get all MSCluster_Resource instances; filter by Type == 'Physical Disk'.
            List<PSObject> resources;
            try
            {
                CimService.CmObjectRequest resourceRequest = new CimService.CmObjectRequest()
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
                // PS: the inlined Get-DbaCmObject MSCluster_Resource lookup (inside the unforwarded
                // Get-DbaWsfcResource) runs WITHOUT -EnableException - warn only, never an error
                // even under the caller's -EnableException; $resources is empty so the loop is a
                // no-op for this computer.
                NestedCommand.WarnUnforwarded(this, ex.Message, computer.ComputerName, ex.InnerException ?? ex);
                continue;
            }

            foreach (PSObject resource in resources)
            {
                // PS: | Where-Object Type -eq 'Physical Disk'
                string? resourceType = resource.Properties["Type"]?.Value?.ToString();
                if (!string.Equals(resourceType, "Physical Disk", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                string? resourceName = resource.Properties["Name"]?.Value?.ToString();
                string? ownerGroup = resource.Properties["OwnerGroup"]?.Value?.ToString();

                // PS: $resources = Get-DbaWsfcResource ... - the resources the PS original
                // consumes are ALREADY augmented by Get-DbaWsfcResource (State string
                // NoteProperty, ClusterName/ClusterFqdn NoteProperties, resource default
                // display set), and that augmented object ships as the ClusterResource
                // property. Replicate the augmentation here so `.ClusterResource.State` etc.
                // match PS (cross-model review 2026-07-07 finding 5).
                object? rawState = resource.Properties["State"]?.Value;
                string? stateName = GetResourceState(rawState);
                if (resource.Properties["State"] is PSNoteProperty)
                {
                    resource.Properties.Remove("State");
                }
                resource.Properties.Add(new PSNoteProperty("State", stateName));
                if (resource.Properties["ClusterName"] is PSNoteProperty)
                {
                    resource.Properties.Remove("ClusterName");
                }
                resource.Properties.Add(new PSNoteProperty("ClusterName", clusterName));
                if (resource.Properties["ClusterFqdn"] is PSNoteProperty)
                {
                    resource.Properties.Remove("ClusterFqdn");
                }
                resource.Properties.Add(new PSNoteProperty("ClusterFqdn", clusterFqdn));
                OutputHelper.SetDefaultDisplayPropertySet(resource,
                    "ClusterName", "ClusterFqdn", "Name", "State", "Type", "OwnerGroup", "OwnerNode",
                    "PendingTimeout", "PersistentState", "QuorumCapable",
                    "RequiredDependencyClasses", "RequiredDependencyTypes",
                    "RestartAction", "RestartDelay", "RestartPeriod", "RestartThreshold",
                    "RetryPeriodOnFailure", "SeparateMonitor");

                // PS: $disks = $resource | Get-CimAssociatedInstance -ResultClassName MSCluster_Disk
                List<PSObject> disks;
                try
                {
                    CimService.CmAssociationRequest diskAssocReq = new CimService.CmAssociationRequest()
                    {
                        ComputerName = computer.ComputerName,
                        Credential = Credential,
                        SourceObject = resource,
                        ResultClassName = "MSCluster_Disk",
                        Namespace = @"root\MSCluster"
                    };
                    CimService.CmObjectResult diskResult = CimService.GetAssociatedCmObjects(diskAssocReq);
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
                    // PS: $diskpart = $disk | Get-CimAssociatedInstance -ResultClassName MSCluster_DiskPartition
                    List<PSObject> partitions;
                    try
                    {
                        CimService.CmAssociationRequest partAssocReq = new CimService.CmAssociationRequest()
                        {
                            ComputerName = computer.ComputerName,
                            Credential = Credential,
                            SourceObject = disk,
                            ResultClassName = "MSCluster_DiskPartition",
                            Namespace = @"root\MSCluster"
                        };
                        CimService.CmObjectResult partResult = CimService.GetAssociatedCmObjects(partAssocReq);
                        foreach (ErrorRecord passthrough in partResult.PassthroughErrors)
                        {
                            WriteError(NestedCommand.PreserveErrorIdentity(passthrough));
                        }
                        partitions = partResult.Instances;
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

                    // PS: $diskpart = $disk | Get-CimAssociatedInstance -ResultClassName MSCluster_DiskPartition
                    // NO inner loop - the PS original emits exactly ONE object per DISK. $diskpart is
                    // null (no partitions), a single instance, or an array (cross-model review
                    // 2026-07-07 finding 6).
                    if (partitions.Count > 1)
                    {
                        // PS: [dbasize]($diskpart.TotalSize * 1MB) - member enumeration over a
                        // multi-partition array replicates the array 1MB times and the [dbasize]
                        // cast then fails statement-terminating: the PS original surfaces an
                        // ERROR and emits NO object for a multi-partition disk. Replicated
                        // without the pathological array allocation.
                        InvalidCastException multiPartError = new InvalidCastException(
                            "Cannot convert the \"System.Object[]\" value of type \"System.Object[]\" to type \"Dataplat.Dbatools.Utility.Size\".");
                        WriteError(new ErrorRecord(multiPartError, "ConvertToFinalInvalidCastException", ErrorCategory.InvalidArgument, null));
                        continue;
                    }

                    PSObject? diskpart = partitions.Count == 1 ? partitions[0] : null;

                    // PS: [dbasize]($diskpart.TotalSize * 1MB) - a null $diskpart or null TotalSize
                    // propagates null through the multiplication and the cast: the property lands
                    // null, never Size(0).
                    object? rawTotalSize = diskpart?.Properties["TotalSize"]?.Value;
                    object? rawFreeSpace = diskpart?.Properties["FreeSpace"]?.Value;
                    Size? sizeObj = rawTotalSize != null ? new Size(Convert.ToInt64(rawTotalSize) * 1048576L) : null;
                    Size? freeObj = rawFreeSpace != null ? new Size(Convert.ToInt64(rawFreeSpace) * 1048576L) : null;

                    // PS: [PSCustomObject]@{ ... } | Select-DefaultView -ExcludeProperty ClusterDisk, ClusterDiskPart, ClusterResource
                    // new PSObject() TypeNames[0] = PSObject; insert PSCustomObject at 0 to match [PSCustomObject]@{} parity.
                    PSObject output = new PSObject();
                    output.TypeNames.Insert(0, "System.Management.Automation.PSCustomObject");
                    output.Properties.Add(new PSNoteProperty("ClusterName", clusterName));
                    output.Properties.Add(new PSNoteProperty("ClusterFqdn", clusterFqdn));
                    output.Properties.Add(new PSNoteProperty("ResourceGroup", ownerGroup));
                    output.Properties.Add(new PSNoteProperty("Disk", resourceName));
                    output.Properties.Add(new PSNoteProperty("State", stateName));
                    output.Properties.Add(new PSNoteProperty("FileSystem", diskpart?.Properties["FileSystem"]?.Value));
                    output.Properties.Add(new PSNoteProperty("Path", diskpart?.Properties["Path"]?.Value));
                    output.Properties.Add(new PSNoteProperty("Label", diskpart?.Properties["VolumeLabel"]?.Value));
                    output.Properties.Add(new PSNoteProperty("Size", sizeObj));
                    output.Properties.Add(new PSNoteProperty("Free", freeObj));
                    output.Properties.Add(new PSNoteProperty("MountPoints", diskpart?.Properties["MountPoints"]?.Value));
                    output.Properties.Add(new PSNoteProperty("SerialNumber", diskpart?.Properties["SerialNumber"]?.Value));
                    output.Properties.Add(new PSNoteProperty("ClusterDisk", disk));
                    output.Properties.Add(new PSNoteProperty("ClusterDiskPart", diskpart));
                    output.Properties.Add(new PSNoteProperty("ClusterResource", resource));

                    // Select-DefaultView -ExcludeProperty ClusterDisk, ClusterDiskPart, ClusterResource
                    OutputHelper.SetDefaultDisplayPropertySetExcluding(output, new string[] { "ClusterDisk", "ClusterDiskPart", "ClusterResource" });

                    WriteObject(output);
                }
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

    // Port of private/functions/Get-ResourceState.ps1: converts the numeric MSCluster_Resource
    // State property to the human-readable string the PS implementation attaches via Add-Member.
    // The PS `switch ($state) { 2 { ... } }` compares each integer label against the raw value
    // with PS -eq scalar semantics - NOT Convert.ToInt32. That distinction is observable: "2"
    // and 2.0 and [decimal]2 MATCH (label 2 coerces to the value's type and compares equal), but
    // "02", 2.4 and any [bool] do NOT (no branch, no default -> null). Convert.ToInt32 over-coerced
    // all of those into false matches (cross-model return-sweep 2026-07-20). LanguagePrimitives.Equals
    // reproduces the switch's per-label coercion; the [bool] guard reproduces the switch NOT
    // numeric-coercing booleans. Verified 14/14 against a live PS switch.
    private static string? GetResourceState(object? state)
    {
        if (state is null)
        {
            return null;
        }

        // PS `switch` does NOT numeric-coerce a [bool] to match an integer label (unlike -eq's
        // [bool] cast), so $true/$false fall through to null.
        if (state is bool)
        {
            return null;
        }

        // PS `switch ($state)` treats a [char] like its 1-char string (probed: [char]'0'..'4'
        // match cases 0..4 - e.g. [char]'2' -> "Online" - via the char's string form, NOT its
        // code point). LanguagePrimitives.Equals(char, int) would instead cast the int label to a
        // NUL char and miss, so normalize a char to its string form to match PS. (Unreachable for
        // the live WMI uint State, but faithful - cross-model return-sweep r2.)
        if (state is char stateChar)
        {
            state = stateChar.ToString();
        }

        foreach ((int value, string name) in ResourceStateLabels)
        {
            if (LanguagePrimitives.Equals(state, value, ignoreCase: true, CultureInfo.InvariantCulture))
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
