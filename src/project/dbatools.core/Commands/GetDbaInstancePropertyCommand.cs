#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves comprehensive SQL Server instance configuration properties for auditing and comparison</summary>
[Cmdlet(VerbsCommon.Get, "DbaInstanceProperty", DefaultParameterSetName = "Default")]
public sealed class GetDbaInstancePropertyCommand : DbaInstanceCmdlet
{
    // PS: Add-Member -Force replaces these members an earlier call left on the same SMO object.
    private static readonly string[] NoteNames = { "ComputerName", "InstanceName", "SqlInstance", "PropertyType" };

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Specifies which SQL Server instance properties to include from Information, UserOptions, and Settings collections.</summary>
    [Parameter(Position = 2)]
    public object[]? InstanceProperty { get; set; }

    /// <summary>Specifies which SQL Server instance properties to exclude from the results.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeInstanceProperty { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            Server? server = ConnectInstance(instance, "Failure");
            if (server is null)
                continue;

            // PS: three try blocks, each ending in Stop-Function ... -Continue, which goes on to the next instance.
            if (!TryEmit(server, instance, "Information", "Issue gathering information properties for {0}."))
                continue;
            if (!TryEmit(server, instance, "UserOption", "Issue gathering user options for {0}."))
                continue;
            TryEmit(server, instance, "Setting", "Issue gathering settings for {0}.");
        }
    }

    private bool TryEmit(Server server, DbaInstanceParameter instance, string propertyType, string failureFormat)
    {
        try
        {
            PropertyCollection properties;
            if (propertyType == "Information")
                properties = server.Information.Properties;
            else if (propertyType == "UserOption")
                properties = server.UserOptions.Properties;
            else
                properties = server.Settings.Properties;
            EmitProperties(properties, server, propertyType);
            return true;
        }
        catch (PipelineStoppedException)
        {
            // A downstream Select-Object -First stopping the pipeline is engine flow control, never a gathering failure.
            throw;
        }
        catch (Exception ex)
        {
            ErrorRecord record = new ErrorRecord(ex, string.Format("dbatools_{0}", MyInvocation.MyCommand.Name), ErrorCategory.NotSpecified, instance);
            StopFunction(string.Format(failureFormat, instance), target: instance, errorRecord: record, continueLoop: true);
            return false;
        }
    }

    private void EmitProperties(PropertyCollection properties, Server server, string propertyType)
    {
        List<Property> selected = new List<Property>();
        foreach (Property prop in properties)
            selected.Add(prop);

        // Correction instanceproperty-wildcards: the help documents wildcards for both filters, which the pinned
        // Where-Object Name -In / -NotIn never matched; the shared rule E+ matcher keeps every real name literal.
        List<string> scope = selected.ConvertAll(prop => prop.Name);
        // PS: if ($InstanceProperty) { ... | Where-Object Name -In $InstanceProperty }
        if (LanguagePrimitives.IsTrue(InstanceProperty))
        {
            WildcardNameMatcher include = WildcardNameFilter.CreateMatcher(InstanceProperty, true,
                (value, name) => PsOps.Eq(value, name), scope);
            selected = selected.FindAll(prop => include.Matches(prop.Name));
        }
        // PS: if ($ExcludeInstanceProperty) { ... | Where-Object Name -NotIn $ExcludeInstanceProperty }
        if (LanguagePrimitives.IsTrue(ExcludeInstanceProperty))
        {
            WildcardNameMatcher exclude = WildcardNameFilter.CreateMatcher(ExcludeInstanceProperty, true,
                (value, name) => PsOps.Eq(value, name), scope);
            selected = selected.FindAll(prop => !exclude.Matches(prop.Name));
        }

        foreach (Property prop in selected)
        {
            // PS: Add-Member -Force replaces the members an earlier call left on the same SMO object.
            PSObject wrapped = PSObject.AsPSObject(prop);
            foreach (string name in NoteNames)
                wrapped.Properties.Remove(name);
            OutputHelper.AddInstanceProperties(wrapped, server);
            wrapped.Properties.Add(new PSNoteProperty("PropertyType", propertyType));

            // PS: Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Name, Value, PropertyType
            OutputHelper.SetDefaultDisplayPropertySet(wrapped,
                "ComputerName", "InstanceName", "SqlInstance", "Name", "Value", "PropertyType");

            WriteObject(wrapped);
        }
    }
}
