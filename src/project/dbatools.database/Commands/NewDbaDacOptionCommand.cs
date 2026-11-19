#nullable enable

using System;
using System.Collections;
using System.ComponentModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Microsoft.SqlServer.Dac;

namespace Dataplat.Dbatools.Commands;

// Creates DacFx extract, export, publish or import options with optional property values
// and publish-profile deployment settings.
/// <summary>Creates a new Microsoft.SqlServer.Dac.DacExtractOptions/DacExportOptions object depending on the chosen Type</summary>
[Cmdlet(VerbsCommon.New, "DbaDacOption", SupportsShouldProcess = true)]
public sealed class NewDbaDacOptionCommand : DbaBaseCmdlet
{
    /// <summary>The package type the options apply to.</summary>
    [Parameter(Position = 0)]
    [ValidateSet("Dacpac", "Bacpac")]
    [PsStringCast]
    public string Type { get; set; } = "Dacpac";

    /// <summary>Whether the options describe a publish or an export.</summary>
    [Parameter(Mandatory = true, Position = 1)]
    [ValidateSet("Publish", "Export")]
    [PsStringCast]
    public string Action { get; set; } = null!;

    /// <summary>A publish profile XML whose DeployOptions are loaded into the result.</summary>
    [Parameter(Position = 2)]
    [PsStringCast]
    public string? PublishXml { get; set; }

    /// <summary>Property values applied to the generated options object.</summary>
    [Parameter(Position = 3)]
    public Hashtable? Property { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted || !ShouldProcess(Type, String.Format("Creating New DacOptions of {0}", Action)))
            return;

        bool dacpac = String.Equals(Type, "Dacpac", StringComparison.OrdinalIgnoreCase);
        if (String.Equals(Action, "Export", StringComparison.OrdinalIgnoreCase))
        {
            object? options = dacpac
                ? CreateOptions<DacExtractOptions>(Property)
                : CreateOptions<DacExportOptions>(Property);
            if (options != null)
                WriteObject(options);
            return;
        }

        if (!dacpac)
        {
            DacImportOptions? options = CreateOptions<DacImportOptions>(Property);
            if (options != null)
                WriteObject(options);
            return;
        }

        PublishOptions? output = CreateOptions<PublishOptions>(Property);
        if (!String.IsNullOrEmpty(PublishXml))
        {
            DacDeployOptions deployment;
            try
            {
                deployment = DacProfile.Load(PublishXml).DeployOptions;
            }
            catch (Exception error)
            {
                MethodInvocationException invocationError = new MethodInvocationException(
                    String.Format("Exception calling \"Load\" with \"1\" argument(s): \"{0}\"", error.Message), error);
                StopFunction("Could not load profile.", errorRecord:
                    new ErrorRecord(invocationError, "DotNetMethodException", ErrorCategory.NotSpecified, null));
                return;
            }
            if (output == null)
            {
                StopFunction("Could not load profile.", errorRecord: NullAssignmentError("DeployOptions"));
                return;
            }
            output.DeployOptions = deployment;
        }
        else
        {
            object? deploymentProperties = FindProperty("DeployOptions");
            DacDeployOptions? deployment = CreateOptions<DacDeployOptions>(BindHelperProperty(deploymentProperties));
            // The source evaluates the helper before assigning, even after PublishOptions failed.
            if (output == null)
                WriteError(NullAssignmentError("DeployOptions"));
            else
                output.DeployOptions = deployment;
        }

        if (FindProperty("GenerateDeploymentScript") == null)
        {
            if (output == null)
                WriteError(NullAssignmentError("GenerateDeploymentScript"));
            else
                output.GenerateDeploymentScript = false;
        }
        if (output != null)
            WriteObject(output);
    }

    private T? CreateOptions<T>(Hashtable? values) where T : class, new()
    {
        T? options = null;
        ErrorRecord? failure;
        try
        {
            options = new T();
            failure = ApplyProperties(options, values);
        }
        catch (Exception error)
        {
            MethodInvocationException invocationError = new MethodInvocationException(
                String.Format("Exception calling \".ctor\" with \"0\" argument(s): \"{0}\"", error.Message), error);
            failure = new ErrorRecord(invocationError, "ConstructorInvokedThrowException", ErrorCategory.InvalidOperation, null);
        }
        if (failure != null)
        {
            ReportHelperFailure(String.Format("Could not generate object {0}", typeof(T).FullName), failure);
            return null;
        }
        return options;
    }

    private static ErrorRecord? ApplyProperties(object options, Hashtable? values)
    {
        if (values == null)
            return null;

        // Only descriptors on newly constructed DacFx objects are used, never ETS members.
        PropertyDescriptorCollection properties = TypeDescriptor.GetProperties(options, true);
        foreach (DictionaryEntry entry in values)
        {
            string name = (string)LanguagePrimitives.ConvertTo(entry.Key, typeof(string), CultureInfo.InvariantCulture);
            PropertyDescriptor? property = properties.Find(name, true);
            if (property == null)
            {
                InvalidOperationException error = new InvalidOperationException(
                    String.Format("The member \"{0}\" was not found for the specified .NET object.", name));
                return new ErrorRecord(error, "InvalidOperationException", ErrorCategory.InvalidOperation, null);
            }
            if (property.IsReadOnly)
                return InvalidPropertyValue();

            try
            {
                object? value = entry.Value;
                if (property.PropertyType == typeof(DacDeployOptions) && value is Hashtable deploymentValues)
                {
                    DacDeployOptions deployment = new DacDeployOptions();
                    if (ApplyProperties(deployment, deploymentValues) != null)
                        return InvalidPropertyValue();
                    value = deployment;
                }
                else
                {
                    value = LanguagePrimitives.ConvertTo(value, property.PropertyType, CultureInfo.InvariantCulture);
                }
                property.SetValue(options, value);
            }
            catch (Exception)
            {
                // New-Object deliberately replaces setter/conversion details with this record.
                return InvalidPropertyValue();
            }
        }
        return null;
    }

    private static ErrorRecord InvalidPropertyValue()
    {
        Exception error = new Exception("The value supplied is not valid, or the property is read-only. Change the value, and then try again.");
        return new ErrorRecord(error, "SetValueException", ErrorCategory.InvalidData, null);
    }

    /// <summary>
    /// Binds a value to the helper's [hashtable]$Property parameter. When the binder cannot convert it,
    /// the source's helper call fails with a statement-terminating ParameterArgumentTransformationError.
    /// Pester and any caller try/catch see it as terminating, and a cmdlet cannot observe an enclosing
    /// try, so the port terminates. -EnableException does not apply because Stop-Function is not reached.
    /// </summary>
    private Hashtable? BindHelperProperty(object? value)
    {
        if (value == null)
            return null;
        try
        {
            return (Hashtable)LanguagePrimitives.ConvertTo(value, typeof(Hashtable), CultureInfo.InvariantCulture);
        }
        catch (PSInvalidCastException castError)
        {
            ArgumentTransformationMetadataException transformError =
                new ArgumentTransformationMetadataException(castError.Message, castError);
            ParameterBindingException bindingError = new ParameterBindingException(String.Format(
                "Cannot process argument transformation on parameter 'Property'. {0}", transformError.Message), transformError);
            // caller-try: terminate -- continuing would emit PublishOptions with DeployOptions silently dropped
            ErrorRecord record = new ErrorRecord(bindingError, "ParameterArgumentTransformationError", ErrorCategory.InvalidData, null);
            ThrowTerminatingError(record); // style-ok: cs-raw-streams binder fault outside Stop-Function, as in the source
            return null;
        }
    }

    private static ErrorRecord NullAssignmentError(string name)
    {
        RuntimeException error = new RuntimeException(String.Format(
            "The property '{0}' cannot be found on this object. Verify that the property exists and can be set.", name));
        return new ErrorRecord(error, "PropertyNotFound", ErrorCategory.InvalidOperation, null);
    }

    private void ReportHelperFailure(string message, ErrorRecord failure)
    {
        MessageService.MessageRequest request = new MessageService.MessageRequest
        {
            FunctionName = "New-DacObject",
            ModuleName = "dbatools",
            Level = MessageLevel.Warning,
            Message = message,
            EnableException = EnableException.ToBool(),
            SuppressWarningDisplay = EnableException.ToBool(),
            FromStopFunction = true,
            File = MyInvocation.ScriptName,
            Line = MyInvocation.ScriptLineNumber
        };
        Exception transformed = MessageService.ResolveException(this, request, failure.Exception);
        ErrorRecord input = ReferenceEquals(transformed, failure.Exception) ? failure :
            new ErrorRecord(transformed, failure.FullyQualifiedErrorId, failure.CategoryInfo.Category, failure.TargetObject);
        ErrorRecord record = new ErrorRecord(new Exception(MessageService.GetErrorMessage(input), input.Exception),
            "dbatools_New-DacObject", input.CategoryInfo.Category, null);
        request.ErrorRecord = new[] { record };
        MessageService.Write(this, request);
        if (EnableException)
        {
            // StopFunction attributes to the public command, but this absorbed helper has its own semantic ID.
            ThrowTerminatingError(record); // style-ok: cs-raw-streams preserve helper attribution after the normal native message path
        }

        // Stop-Function's redirected Write-Error uses Continue and inserts into $Error without a visible stream record.
        // Write-Error appends to the global list; an unqualified lookup from a module-scoped caller resolves to that
        // module's $Error instead (as in DbaBaseCmdlet.InsertGlobalError).
        try
        {
            if (SessionState.PSVariable.GetValue("global:Error") is ArrayList errors)
            {
                errors.Insert(0, record);
                int limit;
                if (!Int32.TryParse(Convert.ToString(SessionState.PSVariable.GetValue("MaximumErrorCount"), CultureInfo.InvariantCulture), out limit))
                    limit = 256;
                if (limit >= 0 && errors.Count > limit)
                    errors.RemoveRange(limit, errors.Count - limit);
            }
        }
        catch (Exception)
        {
            // As in the shared native stop path, restricted session state must not replace the original failure.
        }
    }

    private object? FindProperty(string name)
    {
        if (Property == null)
            return null;
        foreach (DictionaryEntry entry in Property)
        {
            if (entry.Key is string key && String.Equals(key, name, StringComparison.OrdinalIgnoreCase))
                return entry.Value;
        }
        return null;
    }
}
